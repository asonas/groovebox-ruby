module Presets
  class Kick < Synthesizer
    attr_accessor :base_note
    def initialize(sample_rate = 44100, amplitude = 1000)
      super(sample_rate, amplitude)

      @envelope.attack  = 0.001
      @envelope.decay   = 0.25
      @envelope.sustain = 0.0
      @envelope.release = 0.2

      @oscillator.waveform = :sine

      @base_note = Note.new.set_by_midi(36) #C1
    end

    def note_on(midi_note, velocity)
      new_note = Note.new

      # ドラムのキックなので鳴らす音階は常に固定する。midi_noteは無視
      new_note.set_by_midi(@base_note.midi_note)
      new_note.phase = 0.0
      new_note.note_on_sample_index = @global_sample_count

      # @velocity = velocity / 127.0

      @active_notes[midi_note] = new_note
      puts "kick note_on: #{midi_note}, velocity=#{velocity}"
    end

    def note_off(midi_note)
      super(midi_note)
    end

    # pitch bendを実装
    def generate(buffer_size)
      start_sample_index = @global_sample_count
      samples = Array.new(buffer_size, 0.0)

      @active_notes.each_value do |note|
        pitch_env_duration = 0.05 # 50msぐらいで急激に下がる
        pitch_ratio = 20.0       # ピッチが一番高い状態の相対比

        wave = @oscillator.generate_wave(note, buffer_size)

        wave.each_with_index do |sample_val, idx|
          current_sample_index = start_sample_index + idx
          time_sec = (current_sample_index - note.note_on_sample_index).to_f / @sample_rate

          # ピッチエンベロープ: time_secがpitch_env_durationに達するまでは
          # pitch_ratioから1.0へ指数的に近づいていくとする
          if time_sec < pitch_env_duration
            t = time_sec / pitch_env_duration
            # 先頭でpitch_ratio倍 -> 最後に1.0倍に近づく計算
            current_pitch_multiplier = 1.0 + (pitch_ratio - 1.0) * (1.0 - t)
          else
            current_pitch_multiplier = 1.0
          end

          # ピッチ補正分をかける
          sample_val *= current_pitch_multiplier

          # Envelope適用
          env_val = @envelope.apply_envelope(note, current_sample_index, @sample_rate)
          wave[idx] = sample_val * env_val
        end

        # 各ノートの波形を足し合わせる
        samples = samples.zip(wave).map { |s1, s2| s1 + s2 }
      end

      master_gain = 10.0
      samples.map! { |sample| sample * master_gain }

      @global_sample_count += buffer_size
      cleanup_inactive_notes(buffer_size)

      samples
    end
  end
end
