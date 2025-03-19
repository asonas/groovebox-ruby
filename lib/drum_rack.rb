# 規定のmidi_noteから4x4のドラムパッドを生成する
# basa_midi_noteが68で4x8のデバイスの場合は以下のようにアサインされる
# 92 93 94 95
# 84 85 86 87
# 76 77 78 79
# 68 69 70 71
class DrumRack
  MAX_TRACKS = 16

  def initialize(base_midi_node)
    @tracks = {}
    @track_volumes = {}
    @base_midi_node = base_midi_node
  end

  def add_track(synth, pad_offset = 0, volume = 1.0)
    midi_note = @base_midi_node + pad_offset
    @tracks[midi_note] = synth
    @track_volumes[midi_note] = volume
  end

  def set_track_volume(midi_note, volume)
    @track_volumes[midi_note] = volume if @tracks.key?(midi_note)
  end

  def note_on(midi_note, velocity)
    if @tracks[midi_note]
      @tracks[midi_note].note_on(midi_note, velocity)
      puts "Note On: #{midi_note}, velocity=#{velocity}"
    end
  end

  def note_off(midi_note)
    if @tracks[midi_note]
      @tracks[midi_note].note_off(midi_note)
      puts "Note Off: #{midi_note}"
    end
  end

  def generate(buffer_size)
    mixed_samples = Array.new(buffer_size, 0.0)
    active_tracks = 0

    @tracks.each do |midi_note, synth|
      samples = synth.generate(buffer_size)
      next if samples.all? { |sample| sample.zero? }

      # トラックごとの音量を適用
      volume = @track_volumes[midi_note] || 1.0
      samples.map! { |sample| sample * volume }

      mixed_samples = mixed_samples.zip(samples).map { |a, b| a + b }
      active_tracks += 1
    end

    # 複数のトラックがアクティブな場合は、平方根スケーリングを使用して
    # より自然な音量調整を行う（単純な割り算よりも音が小さくなりすぎない）
    if active_tracks > 1
      gain_adjustment = 1.0 / Math.sqrt(active_tracks)
      mixed_samples.map! { |sample| sample * gain_adjustment }
    end

    mixed_samples
  end

  def pad_notes
    @tracks.keys
  end
end
