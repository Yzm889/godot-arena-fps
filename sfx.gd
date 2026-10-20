extends RefCounted

const MIX_RATE := 22050


static func shoot() -> AudioStreamWAV:
	var frames := int(MIX_RATE * 0.09)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		var t := float(i) / MIX_RATE
		var progress := float(i) / frames
		var frequency := lerpf(900.0, 180.0, progress)
		var sample := sin(TAU * frequency * t) * (1.0 - progress) * 0.45
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	return _wrap(data)


static func enemy_hit() -> AudioStreamWAV:
	var frames := int(MIX_RATE * 0.08)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		var t := float(i) / MIX_RATE
		var envelope := 1.0 - float(i) / frames
		var sample := (sin(TAU * 220.0 * t) * 0.6 + randf_range(-1.0, 1.0) * 0.4) * envelope * 0.4
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	return _wrap(data)


static func enemy_shoot() -> AudioStreamWAV:
	var frames := int(MIX_RATE * 0.16)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		var t := float(i) / MIX_RATE
		var progress := float(i) / frames
		var frequency := lerpf(520.0, 110.0, progress)
		var sample := (sin(TAU * frequency * t) * 0.7 + sin(TAU * frequency * 2.0 * t) * 0.3) * (1.0 - progress) * 0.35
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	return _wrap(data)


static func player_hurt() -> AudioStreamWAV:
	var frames := int(MIX_RATE * 0.14)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		var envelope := 1.0 - float(i) / frames
		var sample := randf_range(-1.0, 1.0) * envelope * 0.35
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	return _wrap(data)


static func player_death() -> AudioStreamWAV:
	var frames := int(MIX_RATE * 0.6)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		var t := float(i) / MIX_RATE
		var progress := float(i) / frames
		var frequency := lerpf(320.0, 60.0, progress)
		var sample := sin(TAU * frequency * t) * (1.0 - progress) * 0.4
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	return _wrap(data)


static func _wrap(data: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream
