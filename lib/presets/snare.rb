# presets/snare.rb
module Presets
  class Snare < Synthesizer
    attr_accessor :base_note

    def initialize(sample_rate = 44100, amplitude = 1000)
      super(sample_rate, amplitude)

      # 808 Snare-like envelope.
      @envelope.attack  = 0.0001  # Almost instantaneous attack.
      @envelope.decay   = 0.2     # Body decays relatively quickly.
      @envelope.sustain = 0.0     # Sustain is 0 (like percussion, sounds and decays at once).
      @envelope.release = 0.05    # Release is also short.

      # Set the body oscillator to sine wave.
      @oscillator.waveform = :sine

      # 808 snare is typically around 180Hz.
      # MIDI note 54 (F#3) is approx. 185Hz, so fix it here.
      @base_note = Note.new.set_by_midi(54)

      # Example filter initial settings (adjust/disable as desired).
      # @vcf.high_pass_cutoff = 600.0  # e.g., if you want to cut some low frequencies of the noise.
      # @vcf.low_pass_cutoff  = 8000.0 # Keep some high frequencies.
    end

    # Similar to Kick, it's a drum sound, so ignore the MIDI note value itself and play a fixed frequency.
    def note_on(midi_note, velocity)
      new_note = Note.new
      new_note.set_by_midi(@base_note.midi_note)
      new_note.phase = 0.0
      new_note.note_on_sample_index = @global_sample_count

      @active_notes[midi_note] = new_note

      puts "snare note_on: #{midi_note}, velocity=#{velocity}"
    end

    # If no changes are needed, note_off can be the same as the parent class.
    def note_off(midi_note)
      super(midi_note)
    end

    def generate(buffer_size)
      return Array.new(buffer_size, 0.0) if @active_notes.empty?

      start_sample_index = @global_sample_count
      samples = Array.new(buffer_size, 0.0)

      @active_notes.each_value do |note|
        # --- Body part (sine wave) ---
        wave_body = @oscillator.generate_wave(note, buffer_size)

        # --- Noise part (white noise) ---
        wave_noise = Array.new(buffer_size) { (rand * 2.0) - 1.0 }

        # Apply VCF (filter) here if desired.
        # wave_noise.map!.with_index do |val, i|
        #   @vcf.apply(val)
        # end

        # Body/noise volume balance (adjust as needed).
        body_amp  = 0.7
        noise_amp = 0.4

        # Combine body + noise.
        combined_wave = wave_body.zip(wave_noise).map do |b_val, n_val|
          (body_amp * b_val) + (noise_amp * n_val)
        end

        # Apply envelope.
        combined_wave.each_with_index do |sample_val, idx|
          current_sample_index = start_sample_index + idx
          env_val = @envelope.apply_envelope(note, current_sample_index, @sample_rate)

          combined_wave[idx] = sample_val * env_val
        end

        # Combine with other notes (polyphony).
        samples = samples.zip(combined_wave).map { |s1, s2| s1 + s2 }
      end

      # Overall gain.
      master_gain = 1.0
      samples.map! { |sample| sample * master_gain }

      @global_sample_count += buffer_size
      cleanup_inactive_notes(buffer_size)

      samples
    end
  end
end
