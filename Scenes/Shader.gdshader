shader_type canvas_item;

// Compatibility modunda 'sampler2D' veri tipini kullanmalıyız
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

// Pikselleştirme Çözünürlüğü (Örn: 320x240 - Retro His)
uniform vec2 resolution_scale = vec2(320.0, 240.0);
// Renk Derinliği (Örn: kanal başına 5 bit)
uniform float color_depth_bits = 5.0;
// Dither Dokusunun Ölçeği
uniform float dither_scale = 1.0;
// Scanline (CRT Tırtık) Şiddeti
uniform float scanline_strength = 0.15;

// Bayer Matrix 4x4 (Array olarak tanımlıyoruz)
const float bayer_matrix[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
);

void fragment() {
	// 1. Barrel Distortion Kaldırıldı -> Doğrudan SCREEN_UV'yi kullan
	// Sınır kontrolüne gerek kalmadı, siyah çerçeve oluşmayacak.
	vec2 uv = SCREEN_UV;

	// 2. Pikselleştirme (UV bozulmadığı için tam ekran kalır)
	vec2 pixel_uv = floor(uv * resolution_scale) / resolution_scale;
	
	// 3. Renk Örnekleme (Piksellenmiş UV üzerinden)
	vec4 color = texture(screen_texture, pixel_uv);

	// 4. Renk Bantlanması ve Dithering (Retro Doku)
	float depth = pow(2.0, color_depth_bits);
	
	// Bayer indeksi hesabı
	int x = int(mod(FRAGCOORD.x / dither_scale, 4.0));
	int y = int(mod(FRAGCOORD.y / dither_scale, 4.0));
	float dither = bayer_matrix[x + y * 4] / 15.0;

	// Kanal bazlı dither uygula
	vec3 final_rgb = floor(color.rgb * depth + (dither - 0.5)) / depth;

	// 5. Scanlines (CRT Tırtıkları)
	// 'resolution_scale.y'yi kullanarak tırtık sayısını çözünürlüğe bağlıyoruz
	float scanline = sin(pixel_uv.y * resolution_scale.y * 3.14159);
	final_rgb *= 1.0 - (abs(scanline) * scanline_strength);

	// 6. Nihai Renk
	COLOR = vec4(final_rgb, 1.0);
}