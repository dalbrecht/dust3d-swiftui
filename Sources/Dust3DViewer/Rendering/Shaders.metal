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
