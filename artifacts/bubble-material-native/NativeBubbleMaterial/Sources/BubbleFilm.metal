#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

static float gaussian(float2 point, float2 center, float2 width) {
    float2 delta = (point - center) / width;
    return exp(-dot(delta, delta));
}

[[ stitchable ]] half4 pearlFilm(
    float2 position,
    float4 bounds,
    float time,
    float2 pointer,
    float populated,
    float breathing
) {
    float2 uv = (position - bounds.xy) / max(bounds.zw, float2(1.0));
    float2 p = (uv - 0.5) * 2.0;
    float radius = length(p);
    float angle = atan2(p.y, p.x);
    float organic = 1.0 + 0.010 * sin(angle * 3.0 + time * 0.31)
        + 0.0048 * cos(angle * 2.0 - time * 0.22);
    float2 surfacePoint = p * organic;
    float radiusSquared = dot(surfacePoint, surfacePoint);
    float z = sqrt(max(0.035, 1.0 - radiusSquared * 0.88));
    float3 normal = normalize(float3(surfacePoint.x * 0.92, -surfacePoint.y * 0.92, z));
    float3 viewDirection = float3(0.0, 0.0, 1.0);
    float fresnel = pow(1.0 - saturate(dot(normal, viewDirection)), 4.4);

    // A small pointer motion turns a broad, continuous studio environment. Its
    // reflections follow the spherical normals instead of translating a spot.
    float3 reflected = reflect(-viewDirection, normal);
    float rotation = (pointer.x - 0.5) * 0.82 + sin(time * 0.19) * 0.025;
    float2 rotated = float2(
        reflected.x * cos(rotation) - reflected.z * sin(rotation),
        reflected.y + (0.5 - pointer.y) * 0.18
    );

    float sky = smoothstep(-0.62, 0.74, rotated.y);
    float3 environment = mix(float3(0.28, 0.37, 0.52), float3(0.94, 0.84, 0.78), sky);
    environment = mix(environment, float3(0.34, 0.51, 0.65), smoothstep(0.34, 0.91, rotated.z) * 0.42);

    float bend = 0.045 * sin(rotated.y * 3.2 + 0.5);
    float silkbox = gaussian(float2(rotated.x, rotated.y), float2(-0.20 + bend, 0.28), float2(0.13, 0.36));
    float broadbox = gaussian(float2(rotated.x, rotated.y), float2(0.45, -0.18), float2(0.27, 0.21));
    float softReflection = silkbox * 0.68 + broadbox * 0.40;
    environment += float3(0.73, 0.82, 0.91) * silkbox * 0.66;
    environment += float3(0.93, 0.76, 0.69) * broadbox * 0.43;

    float3 lightDirection = normalize(float3((pointer.x - 0.5) * 0.84, (0.5 - pointer.y) * 0.60, 0.88));
    float diffuse = max(dot(normal, lightDirection), 0.0);
    float breathingTint = 0.5 + 0.5 * sin(time * 0.68);
    float3 pearl = mix(float3(0.31, 0.48, 0.61), float3(0.77, 0.80, 0.78), 0.30 + diffuse * 0.42);
    pearl += float3(0.055, 0.050, 0.062) * (breathingTint * (0.55 + populated * 0.30));

    float3 color = mix(pearl, environment, 0.23 + fresnel * 0.58);
    color += float3(0.78, 0.84, 0.90) * softReflection * (0.15 + fresnel * 0.31);

    // Thin-film interference is an angle-sensitive spectral accent confined to
    // reflected light, with no static rainbow perimeter.
    float thickness = 1.7 + 0.42 * radiusSquared
        + 0.15 * sin(surfacePoint.x * 3.2 + surfacePoint.y * 2.1 + time * 0.16)
        + breathing * 0.12;
    float phase = thickness * (1.0 + fresnel * 0.62);
    float3 spectrum = 0.5 + 0.5 * cos(phase * float3(1.21, 1.00, 0.82) + float3(0.2, 2.18, 4.03));
    float illuminatedFilm = saturate(softReflection * 0.72 + fresnel * 0.38);
    color = mix(color, color * 0.72 + spectrum * float3(0.63, 0.69, 0.76), illuminatedFilm * 0.105);

    // The SwiftUI Shape clips the fill to its outline; this feather softens
    // only the final antialiased edge of the pearly shell.
    float edge = 1.0 - smoothstep(0.985, 1.012, radius * organic);
    float alpha = (0.86 + fresnel * 0.10 + softReflection * 0.025) * edge;
    return half4(half3(color * alpha), half(alpha));
}
