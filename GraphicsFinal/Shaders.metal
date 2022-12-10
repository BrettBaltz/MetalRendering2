#include <metal_stdlib>
#include "ShadersDefinitions.metal"
using namespace metal;

#define EYE_LIGHT_X 1.0
#define EYE_LIGHT_Y 1.0
#define EYE_LIGHT_Z 1.0
#define AMBIENT_COEFFICIENT 0.1
#define SPECULAR_EXPONENT 8.0

simd_float3 phong(simd_float4 eyeLight, simd_float4 eyeNormal, simd_float4 eyeView,
            simd_float3 diffuseColor, simd_float3 specularColor);
float luminance(simd_float3 color);
simd_float3 gamma(simd_float3 color);


vertex VertexOut vertexShader(
    const VertexIn vertexIn [[stage_in]],
    constant VertexUniforms &uniforms [[buffer(1)]])
{
    VertexOut output;
    output.position = uniforms.projectionMatrix * uniforms.viewMatrix
                      * uniforms.modelMatrix * vertexIn.position;
    output.texCoord = vertexIn.texCoord;
    output.eyeView = -normalize(uniforms.viewMatrix * uniforms.modelMatrix
                                * vertexIn.position);
    output.eyeNormal = normalize(uniforms.viewMatrix * uniforms.modelMatrix
                                 * simd_float4(vertexIn.normal, 0.0));
    return output;
}

fragment simd_float4 fragmentShader(
    const VertexOut fragmentIn [[stage_in]],
    constant FragmentUniforms &uniforms [[buffer(0)]],
    texture2d<float> diffuseTexture [[texture(0)]],
    texture2d<float> specularTexture [[texture(1)]]
)
{
    simd_float4 eyeLight = normalize(simd_float4(
        EYE_LIGHT_X, EYE_LIGHT_Y, EYE_LIGHT_Z, 0.0
    ));
    
    constexpr sampler textureSampler;
    simd_float3 diffuseColor = simd_float3(
        diffuseTexture.sample(textureSampler, fragmentIn.texCoord));
    simd_float3 specularColor = simd_float3(
        specularTexture.sample(textureSampler, fragmentIn.texCoord));
    
    simd_float3 outputColor = phong(eyeLight, fragmentIn.eyeNormal,
                                    fragmentIn.eyeView, diffuseColor,
                                    specularColor);
    return simd_float4(outputColor, 1.0);
}

simd_float3 phong(
    simd_float4 eyeLight,
    simd_float4 eyeNormal,
    simd_float4 eyeView,
    simd_float3 diffuseColor,
    simd_float3 specularColor
)
{
    simd_float3 ambient = AMBIENT_COEFFICIENT * diffuseColor;
    
    simd_float3 diffuse = max(dot(eyeLight, eyeNormal), 0.0)
                          * diffuseColor
                          * simd_float3(eyeLight);
    
    simd_float4 eyeNormalReflection = reflect(-eyeLight, eyeNormal);
    simd_float3 rdotv = dot(eyeNormalReflection, eyeView);
    simd_float3 specular = step(0.0, dot(eyeLight, eyeNormal))
                           * simd_float3(1.0, 1.0, 1.0)
                           * specularColor
                           * pow(max(rdotv, 0.0), SPECULAR_EXPONENT);
    
    
    return gamma(
        (ambient + diffuse + specular)
        / (1. + luminance(ambient + diffuse + specular))
    );
}

float luminance(simd_float3 color) {
    return 0.2126 * color.x + 0.7152 * color.y + 0.0722 * color.z;
}

// sRGB gamma correction
simd_float3 gamma(simd_float3 color) {
    float exp = 1.0 / 2.4;
    if (color.x < 0.0031308) { color.x *= 12.92; }
    else { color.x = 1.055 * pow(color.x, exp) - 0.055; }
    if (color.y < 0.0031308) { color.y *= 12.92; }
    else { color.y = 1.055 * pow(color.y, exp) - 0.055; }
    if(color.z < 0.0031308) { color.z *= 12.92; }
    else { color.z = 1.055 * pow(color.z, exp) - 0.055; }
    return color;
}
