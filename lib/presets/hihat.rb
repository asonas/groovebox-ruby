# presets/hihat.rb
module Presets
  class HiHat < Synthesizer
    attr_accessor :base_note

    def initialize(sample_rate = 44100, amplitude = 1000)
      super(sample_rate, amplitude)

      @envelope.attack = 0
      @envelope.decay   = 0.04
      @envelope.sustain = 0.0
      @envelope.release = 0.01

      # ============== Oscillator設定 ==============
      # 金属っぽいスクエア系
      @oscillator.waveform = :square
      # いくつか倍音をちょっとズラして入れると金属らしさが増す
      @oscillator.harmonics = [
        [1.0, 1.0],   # 基本(周波数そのまま)
        [2.0, 0.6],   # 2倍音
        [3.1, 0.4],   # 3.1倍音
        [4.2, 0.3],   # 4.2倍音
        [5.4, 0.2],   # 5.4倍音
      ]


      # ============== 基本周波数 ==============
      #   ドラム系なのでハイハットは音階を使わず固定でOK
      #   適当な高めのMIDIノート値をあてて周波数だけ利用します
      @base_note = Note.new.set_by_midi(89) # A#5(=932Hzあたり)など

      # ============== フィルタ設定 ==============
      #   808ハイハットっぽくするなら、バンドパス気味にしたり
      #   下をそこそこ切って上も少し切ると “シャリ” としやすいです
      #   ※ここでは実験的に設定。お好みで変更してください。
      @vcf.high_pass_cutoff = 500.0   # 低域を削ってシャリ感を出す
      @vcf.low_pass_cutoff  = 10000.0 # 高域を適度に残す
    end

    # ハイハットは固定周波数で鳴らすので、midi_noteは無視
    def note_on(midi_note, velocity)
      new_note = Note.new
      new_note.set_by_midi(@base_note.midi_note)
      new_note.phase = 0.0
      new_note.note_on_sample_index = @global_sample_count

      @active_notes[midi_note] = new_note

      puts "hihat note_on: #{midi_note}, velocity=#{velocity}"
    end

    def generate(buffer_size)
      return Array.new(buffer_size, 0.0) if @active_notes.empty?

      start_sample_index = @global_sample_count
      samples = Array.new(buffer_size, 0.0)

      @active_notes.each_value do |note|
        # ========== オシレーター(複数倍音スクエア波) ==========
        wave_body = @oscillator.generate_wave(note, buffer_size)

        # ========== ノイズ(ホワイトノイズ) ==========
        wave_noise = Array.new(buffer_size) { (rand * 2.0) - 1.0 }
        # フィルタをかける (不要ならコメントアウト)
        wave_noise.map!.with_index do |val, i|
          @vcf.apply(val)
        end

        # ========== ボディ + ノイズ 合成 ==========
        body_amp  = 0.3   # スクエア波の割合(小さめに設定)
        noise_amp = 0.7   # ノイズの割合(大きめに設定)
        combined_wave = wave_body.zip(wave_noise).map do |b_val, n_val|
          (body_amp * b_val) + (noise_amp * n_val)
        end

        # ========== エンベロープ適用 ==========
        combined_wave.each_with_index do |sample_val, idx|
          current_sample_index = start_sample_index + idx
          env_val = @envelope.apply_envelope(note, current_sample_index, @sample_rate)
          combined_wave[idx] = sample_val * env_val
        end

        # ========== ノート同士の合成 (複数発音) ==========
        samples = samples.zip(combined_wave).map { |s1, s2| s1 + s2 }
      end

      # 全体ゲイン
      master_gain = 5.0
      samples.map! { |sample| sample * master_gain }

      @global_sample_count += buffer_size
      cleanup_inactive_notes(buffer_size)

      samples
    end
  end
end
