module Presets
  class Bass < Synthesizer
    attr_accessor :bass_note
    attr_accessor :filter_cutoff, :filter_resonance

    def initialize(sample_rate = 44100, amplitude = 1000)
      super(sample_rate, amplitude)

      @envelope.attack = 0.01
      @envelope.decay = 0.2
      @envelope.sustain = 0.4
      @envelope.release = 0.3

      @oscillator.waveform = :sawtooth

      @oscillator.harmonics = [
        [1.0, 1.0], # 基本波
        [2.0, 0.3], # 2倍音
        [0.5, 0.5], # 1オクターブ下、50%の音量
      ]

      @vcf.low_pass_cutoff = 800.0
      @vcf.high_pass_cutoff = 30.0

      @filter_cutoff = 800.0
      @filter_resonance = 0.3

      @bass_note = Note.new.set_by_midi(36) # C1
    end

    # @param midi_note [Integer] MIDIノート番号（入力そのまま使用）
    # @param velocity [Integer] ベロシティ値（0-127）
    def note_on(midi_note, velocity)
      new_note = Note.new
      semitone_diff = midi_note - @bass_note.midi_note
      new_note.set_by_midi(semitone_diff)

      new_note.phase = 0.0
      new_note.note_on_sample_index = @global_sample_count

      new_note.velocity = velocity / 127.0 if velocity

      @active_notes[midi_note] = new_note

      note_name = new_note.name + new_note.octave.to_s
      puts "bass note_on: midi_note=#{midi_note} (#{note_name}), velocity=#{velocity}, frequency=#{new_note.frequency.round(2)}Hz"
    end

    def generate(buffer_size)
      return Array.new(buffer_size, 0.0) if @active_notes.empty?

      samples = Array.new(buffer_size, 0.0)

      start_sample_index = @global_sample_count
      active_note_count = 0

      @active_notes.each_value do |note|
        wave = @oscillator.generate_wave(note, buffer_size)

        wave.each_with_index do |sample_val, idx|
          current_sample_index = start_sample_index + idx
          env_val = @envelope.apply_envelope(note, current_sample_index, @sample_rate)

          wave[idx] = sample_val * env_val
        end

        @vcf.resonance = @filter_resonance
        wave = @vcf.process(wave, :low_pass)

        samples = samples.zip(wave).map { |s1, s2| s1 + s2 }
        has_sound = false
        wave.each do |sample|
          if sample != 0.0
            has_sound = true
            break
          end
        end
        active_note_count += 1 if has_sound
      end

      master_gain = 5.0
      if active_note_count > 1
        master_gain *= (1.0 / Math.sqrt(active_note_count))
      end
      samples.map! { |sample| sample * master_gain }

      @global_sample_count += buffer_size

      cleanup_inactive_notes(buffer_size)

      samples
    end

    private

    def cleanup_inactive_notes(buffer_size)
      @active_notes.delete_if do |note_id, note|
        if note.note_off_sample_index
          final_env = @envelope.apply_envelope(note, @global_sample_count - 1, @sample_rate)
          final_env <= 0.0
        else
          false
        end
      end
    end
  end
end
