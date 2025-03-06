# presets/snare.rb
module Presets
  class Snare < Synthesizer
    attr_accessor :base_note

    def initialize(sample_rate = 44100, amplitude = 1000)
      super(sample_rate, amplitude)

      # 808スネアっぽいエンベロープ
      # ※本物はもう少し複雑ですが、単純化しています
      @envelope.attack  = 0.0001  # ほぼ瞬時に立ち上がる
      @envelope.decay   = 0.2     # ボディが短めに減衰
      @envelope.sustain = 0.0     # サスティンは0（打楽器らしく一気に鳴って減衰）
      @envelope.release = 0.05    # リリースも短め

      # ボディ用オシレーターは正弦波に設定
      @oscillator.waveform = :sine

      # 808スネアはだいたい 180Hz 前後が目安
      # MIDIノート 54 (F#3) は約185Hz なのでここでは固定にする
      @base_note = Note.new.set_by_midi(54)

      # フィルタの初期設定例(好みで調整/無効化してください)
      # @vcf.high_pass_cutoff = 600.0  # ノイズの低域を少し削りたい場合など
      # @vcf.low_pass_cutoff  = 8000.0 # 高域はある程度残す
    end

    # Kick と同様に、ドラム音なので MIDI ノート値自体は無視して固定周波数を鳴らす
    def note_on(midi_note, velocity)
      new_note = Note.new
      new_note.set_by_midi(@base_note.midi_note)
      new_note.phase = 0.0
      new_note.note_on_sample_index = @global_sample_count

      @active_notes[midi_note] = new_note

      puts "snare note_on: #{midi_note}, velocity=#{velocity}"
    end

    # 特に変更がなければ note_off は親クラスと同じでOK
    def note_off(midi_note)
      super(midi_note)
    end

    def generate(buffer_size)
      return Array.new(buffer_size, 0.0) if @active_notes.empty?

      start_sample_index = @global_sample_count
      samples = Array.new(buffer_size, 0.0)

      @active_notes.each_value do |note|
        # --- ボディ部分(正弦波) ---
        wave_body = @oscillator.generate_wave(note, buffer_size)

        # --- ノイズ部分(ホワイトノイズ) ---
        wave_noise = Array.new(buffer_size) { (rand * 2.0) - 1.0 }

        # VCF(フィルタ)をかけたい場合はここで適用
        # wave_noise.map!.with_index do |val, i|
        #   @vcf.apply(val)
        # end

        # ボディ/ノイズの音量バランス(適宜調整してください)
        body_amp  = 0.7
        noise_amp = 0.4

        # ボディ + ノイズ を合成
        combined_wave = wave_body.zip(wave_noise).map do |b_val, n_val|
          (body_amp * b_val) + (noise_amp * n_val)
        end

        # エンベロープを適用
        combined_wave.each_with_index do |sample_val, idx|
          current_sample_index = start_sample_index + idx
          env_val = @envelope.apply_envelope(note, current_sample_index, @sample_rate)

          combined_wave[idx] = sample_val * env_val
        end

        # 他のノート(複数発音)と合成する
        samples = samples.zip(combined_wave).map { |s1, s2| s1 + s2 }
      end

      # 全体ゲイン
      master_gain = 10.0
      samples.map! { |sample| sample * master_gain }

      @global_sample_count += buffer_size
      cleanup_inactive_notes(buffer_size)

      samples
    end
  end
end
