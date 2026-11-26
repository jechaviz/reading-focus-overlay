module main

fn test_premultiply_scales_colour_by_alpha() {
	mut px := [u8(200), 100, 50, 128, 255, 255, 255, 0]
	premultiply_rgba(mut px)
	assert px[0] == 100 && px[3] == 128
	assert px[4] == 0 && px[7] == 0
}

fn test_resize_premul_constant_image_stays_constant() {
	mut src := []u8{len: 4 * 4 * 4}
	for i in 0 .. 16 {
		src[i * 4] = 40
		src[i * 4 + 1] = 30
		src[i * 4 + 2] = 20
		src[i * 4 + 3] = 128
	}
	out := resize_premul(src, 4, 4, 9, 7)
	assert out.len == 9 * 7 * 4
	for i in 0 .. 63 {
		assert out[i * 4] == 40 && out[i * 4 + 3] == 128
	}
}
