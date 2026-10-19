#include <metal_stdlib>
using namespace metal;

struct MeshVertex {
    float4 position;
    float4 normal;
    float4 color;
};

struct Uniforms {
    float4x4 transform;
    float4x4 rotation;
};

struct VertexOutput {
    float4 position [[position]];
    float3 normal;
    float4 color;
};

vertex VertexOutput meshVertex(uint index [[vertex_id]],
    const device MeshVertex* vertices [[buffer(0)]],
    constant Uniforms& uniforms [[buffer(1)]])
{
    VertexOutput output;
    output.position = uniforms.transform * vertices[index].position;
    output.normal = (uniforms.rotation * vertices[index].normal).xyz;
    output.color = vertices[index].color;
    return output;
}

fragment float4 meshFragment(VertexOutput input [[stage_in]])
{
    float3 normal = normalize(input.normal);
    float key = abs(dot(normal, normalize(float3(-0.5, 0.8, 0.7))));
    float fill = abs(dot(normal, normalize(float3(0.6, 0.1, -0.5))));
    return float4(input.color.rgb * (0.25 + 0.55 * key + 0.2 * fill), 1.0);
}

struct BakedMeshVertex {
    float4 position;
    float4 normal;
    float4 color;
    float4 textureCoordinate;
    float4 tangent;
};

struct BakedUniforms {
    float4x4 transform;
    float4x4 rotation;
    float4 eye;
    float4 options;
};

struct BakedVertexOutput {
    float4 position [[position]];
    float3 viewPosition;
    float3 normal;
    float4 color;
    float4 textureCoordinate;
    float4 tangent;
};

float3 bakedNormalize(float3 value, float3 fallback)
{
    float squared = dot(value, value);
    return isfinite(squared) && squared > 1e-12 ? value * rsqrt(squared) : fallback;
}

float3 bakedLinearColor(float3 value)
{
    value = clamp(value, 0.0, 1.0);
    return select(pow((value + 0.055) / 1.055, float3(2.4)), value / 12.92, value <= 0.04045);
}

vertex BakedVertexOutput bakedMeshVertex(uint index [[vertex_id]],
    const device BakedMeshVertex* vertices [[buffer(0)]],
    constant BakedUniforms& uniforms [[buffer(1)]])
{
    BakedVertexOutput output;
    output.position = uniforms.transform * vertices[index].position;
    output.viewPosition = (uniforms.rotation * vertices[index].position).xyz;
    output.normal = (uniforms.rotation * vertices[index].normal).xyz;
    output.tangent = float4((uniforms.rotation * float4(vertices[index].tangent.xyz, 0)).xyz, vertices[index].tangent.w);
    output.color = vertices[index].color;
    output.textureCoordinate = vertices[index].textureCoordinate;
    return output;
}

float3 materialDisplay(float3 baseColor, float3 normal, float metal, float rough, float3 emission, float3 viewingDirection)
{
    float3 view = bakedNormalize(viewingDirection, float3(0, 0, 1));
    float3 light = normalize(float3(-0.5, 0.8, 0.7));
    float3 halfVector = bakedNormalize(view + light, normal);
    float nv = max(dot(normal, view), 0.0);
    float nl = max(dot(normal, light), 0.0);
    float nh = max(dot(normal, halfVector), 0.0);
    float vh = max(dot(view, halfVector), 0.0);
    float a = rough * rough;
    float aSquared = a * a;
    float denominator = nh * nh * (aSquared - 1.0) + 1.0;
    float distribution = aSquared / max(M_PI_F * denominator * denominator, 1e-7);
    float k = (rough + 1.0) * (rough + 1.0) / 8.0;
    float geometry = nv / max(nv * (1.0 - k) + k, 1e-5) * nl / max(nl * (1.0 - k) + k, 1e-5);
    float3 reflectance = mix(float3(0.04), baseColor, metal);
    float3 fresnel = reflectance + (1.0 - reflectance) * pow(1.0 - vh, 5.0);
    float3 specular = distribution * geometry * fresnel / max(4.0 * nv * nl, 1e-4);
    float3 diffuse = (1.0 - fresnel) * (1.0 - metal) * baseColor / M_PI_F;
    float sky = clamp(normal.y * 0.5 + 0.5, 0.0, 1.0);
    float3 ambient = mix(float3(0.10, 0.11, 0.14), float3(0.23, 0.25, 0.28), sky);
    float3 radiance = (diffuse + specular) * 2.5 * nl + baseColor * ambient * (1.0 - metal) + reflectance * ambient * metal + emission;
    // Bounded filmic display mapping; the sRGB attachment performs encoding after linear blending.
    float3 display = clamp((radiance * (2.51 * radiance + 0.03)) / (radiance * (2.43 * radiance + 0.59) + 0.14), 0.0, 1.0);
    return display;
}

fragment float4 bakedMeshFragment(BakedVertexOutput input [[stage_in]],
    bool frontFacing [[front_facing]], constant BakedUniforms& uniforms [[buffer(1)]],
    texture2d<float> colorMap [[texture(0)]], texture2d<float> normalMap [[texture(1)]],
    texture2d<float> metallicMap [[texture(2)]], texture2d<float> roughnessMap [[texture(3)]],
    texture2d<float> emissiveMap [[texture(4)]], sampler materialSampler [[sampler(0)]])
{
    bool mapped = input.textureCoordinate.z > 0.5;
    float2 uv = input.textureCoordinate.xy;
    float4 base = mapped ? colorMap.sample(materialSampler, uv) : float4(bakedLinearColor(input.color.rgb), clamp(input.color.a, 0.0, 1.0));
    if (base.a <= 0.0)
        discard_fragment();
    float3 normal = bakedNormalize(input.normal, float3(0, 0, 1));
    if (!frontFacing)
        normal = -normal;
    if (mapped && input.textureCoordinate.w > 0.5 && uniforms.options.x > 0.5) {
        float3 axis = abs(normal.z) < 0.9 ? float3(0, 0, 1) : float3(0, 1, 0);
        float3 tangent = bakedNormalize(input.tangent.xyz - normal * dot(normal, input.tangent.xyz), bakedNormalize(cross(axis, normal), float3(1, 0, 0)));
        float3 bitangent = cross(normal, tangent) * input.tangent.w;
        float3 sample = normalMap.sample(materialSampler, uv).rgb * 2.0 - 1.0;
        normal = bakedNormalize(tangent * sample.x + bitangent * sample.y + normal * sample.z, normal);
    }
    float metal = mapped ? clamp(metallicMap.sample(materialSampler, uv).r, 0.0, 1.0) : 0.0;
    float rough = mapped ? clamp(roughnessMap.sample(materialSampler, uv).r, 0.045, 1.0) : 1.0;
    float3 emission = mapped ? emissiveMap.sample(materialSampler, uv).rgb : float3(0);
    return float4(materialDisplay(base.rgb, normal, metal, rough, emission, uniforms.eye.xyz - input.viewPosition), base.a);
}


struct ImportedMeshVertex {
    float4 position;
    float4 normal;
    float4 color;
    float4 textureCoordinate;
};
struct ImportedMaterialUniforms {
    float4 baseColor;
    float4 emissiveMetallic;
    float4 parameters;
};
struct ImportedVertexOutput {
    float4 position [[position]];
    float3 viewPosition;
    float3 normal;
    float4 color;
    float3 textureCoordinate;
};

vertex ImportedVertexOutput importedMeshVertex(uint index [[vertex_id]],
    const device ImportedMeshVertex* vertices [[buffer(0)]], constant BakedUniforms& uniforms [[buffer(1)]])
{
    ImportedVertexOutput output;
    output.position = uniforms.transform * vertices[index].position;
    output.viewPosition = (uniforms.rotation * vertices[index].position).xyz;
    output.normal = (uniforms.rotation * vertices[index].normal).xyz;
    output.color = vertices[index].color;
    output.textureCoordinate = vertices[index].textureCoordinate.xyz;
    return output;
}

fragment float4 importedMeshFragment(ImportedVertexOutput input [[stage_in]], bool frontFacing [[front_facing]],
    constant BakedUniforms& uniforms [[buffer(1)]], constant ImportedMaterialUniforms& material [[buffer(2)]],
    texture2d<float> colorMap [[texture(0)]], sampler sourceSampler [[sampler(0)]])
{
    // sRGB texture decoding occurs before filtering; vertex RGB was linearized before interpolation.
    float4 sample = material.parameters.w > 0.5 && input.textureCoordinate.z > 0.5
        ? colorMap.sample(sourceSampler, input.textureCoordinate.xy) : float4(1);
    float4 base = sample * input.color * material.baseColor;
    float alpha = base.a;
    if (material.parameters.z < 0.5) {
        alpha = 1.0;
    } else if (material.parameters.z < 1.5) {
        if (alpha < material.parameters.y)
            discard_fragment();
        alpha = 1.0;
    } else if (alpha <= 0.0) {
        discard_fragment();
    }
    float3 normal = bakedNormalize(input.normal, float3(0, 0, 1));
    if (!frontFacing)
        normal = -normal;
    float metal = clamp(material.emissiveMetallic.w, 0.0, 1.0);
    float rough = clamp(material.parameters.x, 0.045, 1.0);
    return float4(materialDisplay(base.rgb, normal, metal, rough, material.emissiveMetallic.xyz, uniforms.eye.xyz - input.viewPosition), alpha);
}
