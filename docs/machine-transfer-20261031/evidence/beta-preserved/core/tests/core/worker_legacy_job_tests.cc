// SPDX-License-Identifier: MIT
#include <Dust3DWorkerImageDecoder.h>
#include <Dust3DWorkerRuntime.h>
#include <array>
#include <cstdio>
#include <fstream>
#include <iostream>
#include <iterator>
#include <memory>
#include <native/Engine/WorkerFailure.h>
#include <native/Engine/WorkerLegacyBaked.h>
#include <native/Engine/WorkerLegacyRequest.h>
#include <stdexcept>
#include <unistd.h>
using namespace dust3d::worker;
namespace {
void require(bool value, const char* cause)
{
    if (!value)
        throw std::runtime_error(cause);
}
struct DecoderFixture {
    size_t calls = 0;
    std::array<uint8_t, 4> pixel { 17, 23, 41, 0 };
};
Dust3DWorkerImage* decode(void* context, const Dust3DWorkerImageInput* input, Dust3DWorkerImageResult* result)
{
    auto& fixture = *static_cast<DecoderFixture*>(context);
    ++fixture.calls;
    if (!input || !input->encoded_count || !input->model_count || input->maximum_decoded_bytes < 4) {
        *result = dust3d_worker_image_error_create(DUST3D_WORKER_IMAGE_INVALID_INPUT, 17, nullptr, 0);
        return nullptr;
    }
    return dust3d_worker_image_create(1, 1, fixture.pixel.data(), fixture.pixel.size(), input->maximum_decoded_bytes, result);
}
Frame invoke(const char* fixtures, const char* build, const char* name, const Dust3DWorkerDecoders* decoder)
{
    std::ifstream input(std::string(fixtures) + '/' + name, std::ios::binary);
    require(bool(input), "Existing positive job fixture opens");
    Frame request;
    request.payload = { std::istreambuf_iterator<char>(input), {} };
    Dust3DWorkerRequestIdentity identity {};
    identity.document[0] = 1;
    identity.request = 7;
    Dust3DWorkerRequestLegacyOptions options {};
    options.struct_size = sizeof(options);
    options.atlas_texture_size = options.color_size = options.normal_size = options.material_size = 8;
    Dust3DWorkerRequestResult created {};
    std::unique_ptr<Dust3DWorkerRequest, decltype(&dust3d_worker_request_destroy)> encoded(
        dust3d_worker_legacy_request_create(identity, request.payload.data(), request.payload.size(), &options,
            { maximumPayloadBytes, maximumPayloadBytes, 4096 }, &created),
        dust3d_worker_request_destroy);
    require(encoded && created.status == DUST3D_WORKER_REQUEST_OK, "Dedicated C factory owns the complete legacy request");
    size_t count = 0;
    const auto* span = dust3d_worker_request_bytes(encoded.get(), &count);
    const std::vector<uint8_t> bytes(span, span + count);
    request = decodeFrame(bytes.data(), bytes.size(), {});
    const auto sourcePath = std::string(build) + "/legacy-job-input.bin", outputPath = std::string(build) + "/legacy-job-output.bin";
    std::unique_ptr<FILE, decltype(&std::fclose)> source(std::fopen(sourcePath.c_str(), "w+b"), std::fclose), output(std::fopen(outputPath.c_str(), "w+b"), std::fclose);
    require(source && output && std::fwrite(bytes.data(), 1, bytes.size(), source.get()) == bytes.size(), "Owned shared-build test files open and write");
    std::rewind(source.get());
    const auto result = decoder ? dust3d_worker_serve_with_decoders(fileno(source.get()), fileno(output.get()), decoder) : dust3d_worker_serve(fileno(source.get()), fileno(output.get()));
    require(result.status == DUST3D_WORKER_JOB_COMPLETE && result.operation == DUST3D_WORKER_OPERATION_LEGACY_BAKED && result.request_identity == 7,
        "C worker entry point reports complete correlated imported transaction");
    std::fflush(output.get());
    std::rewind(output.get());
    std::vector<uint8_t> response;
    int byte;
    while ((byte = std::fgetc(output.get())) != EOF)
        response.push_back(static_cast<uint8_t>(byte));
    source.reset();
    output.reset();
    std::remove(sourcePath.c_str());
    std::remove(outputPath.c_str());
    auto reply = decodeFrame(response.data(), response.size(), {});
    validateResponseIdentity(reply.header, request.header);
    return reply;
}
}
int main(int argc, char** argv)
{
    try {
        require(argc == 3, "Existing fixture and shared-build directories required");
        DecoderFixture procedural;
        DecoderFixture imported;
        Dust3DWorkerDecoders configuration {};
        configuration.struct_size = sizeof(configuration);
        configuration.imported = { sizeof(Dust3DWorkerImageDecoder), &imported, decode };
        configuration.procedural = { sizeof(Dust3DWorkerImageDecoder), &procedural, decode };
        const auto rendered = invoke(argv[1], argv[2], "ProceduralImage.ds3", &configuration);
        require(rendered.header.kind == FrameKind::response && procedural.calls == 1 && !imported.calls,
            "Legacy job invokes only the explicit procedural callback slot");
        const auto value = decodeLegacyBakedPayload(rendered.payload.data(), rendered.payload.size(), {});
        require(!value.geometry.vertices.empty() && !value.textures.maps[0].empty(), "Complete owned legacy pixels and geometry traverse descriptor job output");
        procedural.pixel = { 255, 0, 0, 255 };
        const auto redReply = invoke(argv[1], argv[2], "ProceduralImage.ds3", &configuration);
        require(redReply.header.kind == FrameKind::response && procedural.calls == 2 && !imported.calls,
            "Opaque red procedural image is decoded by the matching provider");
        const auto redValue = decodeLegacyBakedPayload(redReply.payload.data(), redReply.payload.size(), {});
        require(!redValue.textures.maps[0].empty(), "Red worker reply contains a color level");
        const auto red = redValue.textures.maps[0][0].pixels;
        procedural.pixel = { 0, 0, 255, 255 };
        const auto blueReply = invoke(argv[1], argv[2], "ProceduralImage.ds3", &configuration);
        require(blueReply.header.kind == FrameKind::response && procedural.calls == 3 && !imported.calls,
            "Opaque blue procedural image is decoded by the matching provider");
        const auto blueValue = decodeLegacyBakedPayload(blueReply.payload.data(), blueReply.payload.size(), {});
        require(!blueValue.textures.maps[0].empty(), "Blue worker reply contains a color level");
        const auto blue = blueValue.textures.maps[0][0].pixels;
        require(red.size() == blue.size() && red.size() == 8 * 8 * 4, "Both small color maps retain their expected RGBA layout");
        bool foundContrast = false;
        for (size_t index = 0; index < red.size(); index += 4) {
            foundContrast |= red[index] > red[index + 2] && blue[index + 2] > blue[index];
        }
        require(foundContrast, "Independent opaque red and blue input pixels reach the same baked worker texel");
        const auto plain = invoke(argv[1], argv[2], "Capsule.ds3", nullptr);
        require(plain.header.kind == FrameKind::response, "Untextured legacy job needs no platform decoder");
        const auto unavailable = invoke(argv[1], argv[2], "ProceduralImage.ds3", nullptr);
        require(unavailable.header.kind == FrameKind::failure && decodeFailurePayload(unavailable.payload.data(), unavailable.payload.size(), {}).status == FailureStatus::unsupportedAsset,
            "Missing procedural provider reports explicit failure without parent fallback");
    } catch (const std::exception& cause) {
        std::cerr << cause.what() << '\n';
        return 1;
    }
    return 0;
}
