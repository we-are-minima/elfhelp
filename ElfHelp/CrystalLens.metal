#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

[[ stitchable ]] half4 crystalLens(float2 position, half4 color, float2 size, float morph) {
    float2 radius = max(size * 0.5, float2(1));
    float2 p = (position - radius) / radius;
    float radialSquared = min(dot(p, p), 1.0);
    float radial = sqrt(radialSquared);
    // Starts at 0.12 so bubbles below that threshold can skip the shader with no visible jump.
    float strength = smoothstep(0.12, 0.48, morph);

    // No refraction: the photo is never distorted, only tinted with the glass reflections.
    float rim = smoothstep(0.70, 0.99, radial);
    float underside = rim * smoothstep(0.30, 0.92, p.y);
    color.rgb *= half(1.0 - 0.23 * underside * strength);

    float upperDirection = dot(p, float2(-0.59, -0.81));
    float lowerDirection = dot(p, float2(0.67, 0.74));
    float upperArc = smoothstep(0.53, 0.92, upperDirection)
        * smoothstep(0.73, 0.88, radial) * (1.0 - smoothstep(0.91, 1.0, radial));
    float lowerArc = smoothstep(0.57, 0.93, lowerDirection)
        * smoothstep(0.75, 0.91, radial) * (1.0 - smoothstep(0.95, 1.0, radial));
    float outerArc = smoothstep(0.90, 0.98, radial)
        * max(smoothstep(0.57, 0.94, upperDirection), smoothstep(0.58, 0.94, lowerDirection));
    color.rgb = mix(color.rgb, color.a * half3(0.94h, 0.88h, 1.0h), half(upperArc * strength * 0.88));
    color.rgb = mix(color.rgb, color.a * half3(1.0h, 0.67h, 0.89h), half(lowerArc * strength * 0.81));
    color.rgb = mix(color.rgb, color.a * half3(0.77h, 0.64h, 1.0h), half(outerArc * strength * 0.58));
    return color;
}
