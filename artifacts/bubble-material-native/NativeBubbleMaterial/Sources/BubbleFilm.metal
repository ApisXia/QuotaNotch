#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

static float studioLobe(float3 ray, float3 center, float angularWidth) {
    float angle = acos(clamp(dot(normalize(ray), normalize(center)), -1.0, 1.0));
    float normalizedAngle = angle / angularWidth;
    return exp(-(normalizedAngle * normalizedAngle));
}

static float studioRibbon(float3 ray, float3 center, float2 angularSize) {
    float3 forward = normalize(center);
    float3 across = normalize(cross(float3(0.0, 1.0, 0.0), forward));
    float3 along = normalize(cross(forward, across));
    float viewDepth = max(dot(normalize(ray), forward), 0.001);
    float2 coordinates = float2(
        atan2(dot(ray, across), viewDepth),
        atan2(dot(ray, along), viewDepth)
    );
    float2 normalized = coordinates / angularSize;
    return exp(-dot(normalized, normalized));
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

    // A sphere reaches a grazing normal at its silhouette. The earlier
    // flattened dome never did, which suppressed its Fresnel reflections.
    float z = sqrt(max(0.001, 1.0 - radiusSquared));
    float3 normal = normalize(float3(surfacePoint.x, -surfacePoint.y, z));
    float3 viewDirection = float3(0.0, 0.0, 1.0);
    float normalView = saturate(dot(normal, viewDirection));
    float fresnel = 0.04 + 0.96 * pow(1.0 - normalView, 5.0);

    // The cursor rotates a broad studio environment. Reflected rays sample
    // its softboxes, so the highlights bend across the spherical normals.
    float3 reflected = reflect(-viewDirection, normal);
    float yaw = (pointer.x - 0.5) * 1.85 + sin(time * 0.19) * 0.025;
    float pitch = (0.5 - pointer.y) * 0.90;
    float3 yawedDirection = float3(
        reflected.x * cos(yaw) - reflected.z * sin(yaw),
        reflected.y,
        reflected.x * sin(yaw) + reflected.z * cos(yaw)
    );
    float3 rotatedDirection = normalize(float3(
        yawedDirection.x,
        yawedDirection.y * cos(pitch) + yawedDirection.z * sin(pitch),
        yawedDirection.z * cos(pitch) - yawedDirection.y * sin(pitch)
    ));

    float sky = smoothstep(-0.42, 0.70, rotatedDirection.y);
    // The key is a stretched studio ribbon near the reflected outer third;
    // the opposite fill is a smaller, softer rounded source.
    float3 coolSource = float3(-0.72, 0.68, 0.14);
    float3 warmSource = float3(0.65, -0.54, 0.53);
    // A grazing surface compresses the reflected strip and gives it a stronger
    // return. The footprint therefore tightens and brightens as the moving
    // environment reflection travels from the face toward the curved rim.
    float grazing = smoothstep(0.18, 0.85, 1.0 - normalView);
    float2 ribbonSize = mix(float2(0.15, 0.40), float2(0.105, 0.31), grazing);
    float2 coreSize = mix(float2(0.055, 0.19), float2(0.040, 0.145), grazing);
    float coolBox = studioRibbon(rotatedDirection, coolSource, ribbonSize);
    float warmBox = studioLobe(rotatedDirection, warmSource, 0.29);
    float coolCore = studioRibbon(rotatedDirection, coolSource, coreSize);
    float warmCore = studioLobe(rotatedDirection, warmSource, 0.13);
    float illuminated = saturate(coolBox * 0.72 + warmBox * 0.64 + coolCore + warmCore);
    float3 environment = mix(float3(0.40, 0.49, 0.61), float3(0.82, 0.77, 0.75), sky);
    environment += float3(0.94, 1.02, 1.10) * coolBox * 2.2;
    environment += float3(1.10, 0.88, 0.78) * warmBox * 1.4;

    float3 lightDirection = normalize(float3((pointer.x - 0.5) * 1.10, (0.5 - pointer.y) * 0.82, 0.86));
    float diffuse = max(dot(normal, lightDirection), 0.0);
    float breathingTint = 0.5 + 0.5 * sin(time * 0.68);
    float3 pearl = mix(float3(0.50, 0.63, 0.75), float3(0.88, 0.88, 0.88), 0.24 + diffuse * 0.42);
    pearl += float3(0.030, 0.024, 0.034) * (breathingTint * (0.55 + populated * 0.30));

    // Thin-film interference appears only inside illuminated reflections.
    float thickness = 1.7 + 0.42 * radiusSquared
        + 0.15 * sin(surfacePoint.x * 3.2 + surfacePoint.y * 2.1 + time * 0.16)
        + breathing * 0.12;
    float phase = thickness * (1.0 + (1.0 - normalView) * 0.62);
    float3 spectrum = 0.5 + 0.5 * cos(phase * float3(1.21, 1.00, 0.82) + float3(0.2, 2.18, 4.03));
    float3 reflectedColor = mix(environment, environment * 0.72 + spectrum * float3(0.72, 0.80, 0.92), illuminated * 0.18);

    // Keep the softly tinted transmitted body separate from Fresnel reflection
    // so the interior stays airy while edge reflections retain their own light.
    float bodyAlpha = 0.12 + diffuse * 0.020 + breathing * 0.005;
    float reflectionAlpha = fresnel * 0.88;
    float baseAlpha = reflectionAlpha + bodyAlpha * (1.0 - reflectionAlpha);
    float3 basePremultiplied = pearl * bodyAlpha * (1.0 - reflectionAlpha)
        + reflectedColor * reflectionAlpha;

    // Art-directed area-light energy keeps studio reflections legible at the
    // 4% normal-incidence Fresnel level. Broad lobes carry the curved sheen;
    // their narrower cores give the surface a polished highlight. Both remain
    // attached to reflected rays, so cursor motion turns the environment.
    float grazingReturn = mix(1.0, 1.45, grazing);
    float coolCoverage = (coolBox * 0.20 + coolCore * 0.40) * grazingReturn;
    float warmCoverage = (warmBox * 0.10 + warmCore * 0.14) * grazingReturn;
    float softboxCoverage = saturate(coolCoverage + warmCoverage);
    float3 softboxColor = (
        float3(0.78, 0.90, 1.00) * coolCoverage
        + float3(1.00, 0.86, 0.78) * warmCoverage
    ) / max(coolCoverage + warmCoverage, 0.001);
    softboxColor = mix(softboxColor, spectrum, softboxCoverage * 0.14);
    float3 premultiplied = basePremultiplied * (1.0 - softboxCoverage)
        + softboxColor * softboxCoverage;
    float alpha = baseAlpha + softboxCoverage * (1.0 - baseAlpha);

    // The SwiftUI Shape clips the fill to its outline; this feather softens
    // only the final antialiased edge of the pearly shell.
    float edge = 1.0 - smoothstep(0.985, 1.012, radius * organic);
    return half4(half3(premultiplied * edge), half(alpha * edge));
}
