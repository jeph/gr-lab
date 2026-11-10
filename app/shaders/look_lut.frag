#version 460 core

// Draws a photo through a colour table (LookLut): each pixel's colour is
// looked up in the table and replaced by what the table holds for it.
// Knows nothing about cameras; the table carries the whole look.

#include <flutter/runtime_effect.glsl>

precision highp float;

// The size of the area drawn, in the canvas's own units.
uniform vec2 uSize;
// The part of the photo shown, as the origin and size of a rectangle in
// the photo's 0..1 coordinates.
uniform vec4 uShown;
// The table's steps per channel.
uniform float uSteps;
uniform sampler2D uPhoto;
// The table: uSteps * uSteps by uSteps pixels, the entry for steps
// (r, g, b) at column b * uSteps + r of row g.
uniform sampler2D uTable;

out vec4 fragColor;

// The table's entry for whole steps, read at the centre of its pixel so
// the result does not depend on how the sampler filters.
vec3 entry(float r, float g, float b) {
  vec2 at = vec2((b * uSteps + r + 0.5) / (uSteps * uSteps), (g + 0.5) / uSteps);
  return texture(uTable, at).rgb;
}

void main() {
  vec2 place = FlutterFragCoord().xy / uSize;
  vec3 colour = texture(uPhoto, uShown.xy + place * uShown.zw).rgb;

  // Blend the eight entries around the colour.
  vec3 steps = clamp(colour, 0.0, 1.0) * (uSteps - 1.0);
  vec3 low = min(floor(steps), uSteps - 2.0);
  vec3 high = low + 1.0;
  vec3 part = steps - low;
  vec3 lowBlue = mix(
    mix(entry(low.r, low.g, low.b), entry(high.r, low.g, low.b), part.r),
    mix(entry(low.r, high.g, low.b), entry(high.r, high.g, low.b), part.r),
    part.g
  );
  vec3 highBlue = mix(
    mix(entry(low.r, low.g, high.b), entry(high.r, low.g, high.b), part.r),
    mix(entry(low.r, high.g, high.b), entry(high.r, high.g, high.b), part.r),
    part.g
  );
  fragColor = vec4(mix(lowBlue, highBlue, part.b), 1.0);
}
