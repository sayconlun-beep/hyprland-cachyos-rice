#version 440
// Wallpaper transitions for the carousel: one shader, ten effects picked by
// `mode`, going from fromImage to toImage as progress runs 0 -> 1.
//   0 glitch  1 dissolve  2 ripple  3 shatter  4 crt
//   5 pixelate  6 swirl  7 flow  8 slide  9 burn
// With blank = 1 the "from" side is transparent, so a card can appear out of
// nothing. Run compile.sh after editing; QML loads the .qsb.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    float mode;
    float aspect;
    float seed;
    float blank;
};

layout(binding = 1) uniform sampler2D fromImage;
layout(binding = 2) uniform sampler2D toImage;

const float PI = 3.14159265;

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21) + seed * 0.013);
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * noise(p);
        p *= 2.03;
        a *= 0.5;
    }
    return v;
}

vec4 A(vec2 uv) {
    if (blank > 0.5)
        return vec4(0.0);
    return texture(fromImage, clamp(uv, 0.0, 1.0));
}

vec4 B(vec2 uv) {
    return texture(toImage, clamp(uv, 0.0, 1.0));
}

vec2 square(vec2 uv) {
    return uv * vec2(aspect, 1.0);
}

// RGB split, torn rows and blocks flickering between the two images.
vec4 glitch(vec2 uv, float p) {
    float k = sin(p * PI);
    float tick = floor(p * 26.0);
    float row = floor(uv.y * 30.0);
    float tear = step(0.7, hash(vec2(row, tick))) * (hash(vec2(tick, row + 7.0)) - 0.5) * 0.2 * k;
    vec2 q = vec2(uv.x + tear, uv.y);
    float block = hash(floor(uv * vec2(20.0, 12.0)) + vec2(tick * 0.37, 0.0));
    float m = step(block, smoothstep(0.15, 0.85, p));
    float s = 0.03 * k;
    vec4 r = mix(A(q + vec2(s, 0.0)), B(q + vec2(s, 0.0)), m);
    vec4 g = mix(A(q), B(q), m);
    vec4 b = mix(A(q - vec2(s, 0.0)), B(q - vec2(s, 0.0)), m);
    vec4 c = vec4(r.r, g.g, b.b, max(max(r.a, g.a), b.a));
    c.rgb += (hash(uv * 911.0 + vec2(tick)) - 0.5) * 0.35 * k * c.a;
    c.rgb *= 1.0 - 0.15 * k * step(0.5, fract(uv.y * 220.0));
    return c;
}

vec4 dissolve(vec2 uv, float p) {
    vec2 a = square(uv);
    float n = fbm(a * 4.0) * 0.65 + hash(floor(a * 160.0)) * 0.35;
    float m = smoothstep(n - 0.05, n + 0.05, p * 1.2 - 0.1);
    return mix(A(uv), B(uv), m);
}

// A ring spreading from the centre, rippling the picture as it passes.
vec4 ripple(vec2 uv, float p) {
    vec2 d = (uv - 0.5) * vec2(aspect, 1.0);
    float r = length(d);
    float front = p * (0.5 * length(vec2(aspect, 1.0)) + 0.15);
    float wave = sin(r * 55.0 - p * 40.0) * 0.012 * sin(p * PI) * exp(-abs(r - front) * 6.0);
    vec2 q = uv + (d / max(r, 1e-4)) * wave / vec2(aspect, 1.0);
    float m = smoothstep(front + 0.06, front - 0.06, r);
    return mix(A(q), B(q), m);
}

// The old image cracks into shards that fall away one by one.
vec4 shatter(vec2 uv, float p) {
    vec2 g = square(uv) * 6.0;
    vec2 ip = floor(g);
    vec2 fp = fract(g);
    float d1 = 8.0;
    float d2 = 8.0;
    vec2 cell = vec2(0.0);
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 b = vec2(float(i), float(j));
            vec2 o = vec2(hash(ip + b), hash(ip + b + 17.0));
            float d = length(b + o - fp);
            if (d < d1) {
                d2 = d1;
                d1 = d;
                cell = ip + b;
            } else if (d < d2) {
                d2 = d;
            }
        }
    }
    float t = clamp(p * 1.7 - hash(cell + 3.1) * 0.7, 0.0, 1.0);
    if (blank > 0.5)
        return B(uv) * smoothstep(0.0, 1.0, t);
    vec2 drift = vec2((hash(cell + 9.0) - 0.5) * 0.15, 0.45) * t * t;
    vec4 old = A(uv - drift) * (1.0 - smoothstep(0.55, 1.0, t));
    vec4 c = old + B(uv) * (1.0 - old.a);
    float crack = (1.0 - smoothstep(0.0, 0.04, d2 - d1)) * smoothstep(0.0, 0.12, p) * (1.0 - t);
    c.rgb = mix(c.rgb, vec3(1.0), crack * 0.7 * c.a);
    return c;
}

// An old TV switching off to a dot, then the new image switching on.
vec4 crt(vec2 uv, float p) {
    float s = p < 0.5 ? p * 2.0 : (1.0 - p) * 2.0;
    float sy = max(1.0 - smoothstep(0.0, 0.6, s), 0.006);
    float sx = max(1.0 - smoothstep(0.6, 1.0, s), 0.003);
    vec2 q = (uv - 0.5) / vec2(sx, sy) + 0.5;
    float inside = step(abs(uv.x - 0.5), sx * 0.5) * step(abs(uv.y - 0.5), sy * 0.5);
    vec4 c = p < 0.5 ? A(q) : B(q);
    c.rgb *= (1.0 + s * 2.5) * (0.88 + 0.12 * sin(uv.y * 900.0));
    vec4 bg = vec4(0.0, 0.0, 0.0, blank > 0.5 ? 0.0 : 1.0);
    return mix(bg, c, inside);
}

vec4 pixelate(vec2 uv, float p) {
    float k = sin(p * PI);
    float cells = mix(1200.0, 12.0, pow(k, 0.7));
    vec2 n = vec2(cells * aspect, cells);
    vec2 q = k < 0.03 ? uv : (floor(uv * n) + 0.5) / n;
    return mix(A(q), B(q), smoothstep(0.42, 0.58, p));
}

vec4 swirl(vec2 uv, float p) {
    vec2 d = (uv - 0.5) * vec2(aspect, 1.0);
    float radius = 0.5 * length(vec2(aspect, 1.0));
    float ang = sin(p * PI) * 7.0 * pow(max(0.0, 1.0 - length(d) / radius), 2.0);
    float cs = cos(ang);
    float sn = sin(ang);
    vec2 q = vec2(cs * d.x - sn * d.y, sn * d.x + cs * d.y) / vec2(aspect, 1.0) + 0.5;
    return mix(A(q), B(q), smoothstep(0.35, 0.65, p));
}

// Liquid: the picture warps while the new one floods in from the left.
vec4 flow(vec2 uv, float p) {
    vec2 a = square(uv);
    vec2 w = vec2(fbm(a * 2.5 + vec2(p * 1.5, 0.0)), fbm(a * 2.5 + vec2(5.2, p * 1.5))) - 0.5;
    vec2 q = uv + w * 0.14 * sin(p * PI);
    float front = uv.x + (fbm(a * vec2(1.5, 4.0) + 3.0) - 0.5) * 0.5;
    float m = smoothstep(front - 0.15, front + 0.15, p * 1.9 - 0.45);
    return mix(A(q), B(q), m);
}

// The new image pushes in from the right; the old one drifts and darkens.
vec4 slide(vec2 uv, float p) {
    float e = p < 0.5 ? 4.0 * p * p * p : 1.0 - pow(-2.0 * p + 2.0, 3.0) / 2.0;
    float edge = uv.x - (1.0 - e);
    if (edge >= 0.0)
        return B(uv - vec2(1.0 - e, 0.0));
    vec4 old = A(uv + vec2(e * 0.3, 0.0));
    old.rgb *= (1.0 - 0.45 * e) * (1.0 - 0.4 * min(e * 20.0, 1.0) * smoothstep(-0.08, 0.0, edge));
    return old;
}

// Burns away along a noisy front with a glowing, charred edge.
vec4 burn(vec2 uv, float p) {
    float n = clamp((fbm(square(uv) * 3.0) - 0.22) / 0.56, 0.0, 1.0);
    float dist = (p * 1.3 - 0.15) - n;          // > 0 once burned through
    float live = step(0.001, p) * step(p, 0.999);
    float m = smoothstep(-0.015, 0.015, dist);
    float edge = (1.0 - smoothstep(0.0, 0.07, abs(dist))) * live;
    vec3 fire = mix(vec3(0.95, 0.25, 0.02), vec3(1.0, 0.8, 0.35), 1.0 - smoothstep(0.0, 0.025, abs(dist)));
    vec4 old = A(uv);
    old.rgb *= 1.0 - 0.6 * (1.0 - smoothstep(0.0, 0.12, -dist)) * live;
    vec4 c = mix(old, B(uv), m);
    c.rgb += fire * edge * 1.2;
    c.a = max(c.a, edge);
    return c;
}

void main() {
    vec2 uv = qt_TexCoord0;
    float p = clamp(progress, 0.0, 1.0);
    int m = int(mode + 0.5);
    vec4 c;
    if (m == 0)
        c = glitch(uv, p);
    else if (m == 1)
        c = dissolve(uv, p);
    else if (m == 2)
        c = ripple(uv, p);
    else if (m == 3)
        c = shatter(uv, p);
    else if (m == 4)
        c = crt(uv, p);
    else if (m == 5)
        c = pixelate(uv, p);
    else if (m == 6)
        c = swirl(uv, p);
    else if (m == 7)
        c = flow(uv, p);
    else if (m == 8)
        c = slide(uv, p);
    else
        c = burn(uv, p);
    c = clamp(c, 0.0, 1.0);
    c.rgb = min(c.rgb, vec3(c.a));              // stay premultiplied
    fragColor = c * qt_Opacity;
}
