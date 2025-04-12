module Presets
  class HihatClosed < Synthesizer
    def initialize(sample_rate = 44100, amplitude = 1000)
      super(sample_rate, amplitude)

      @oscillator.waveform = :square

      # Short envelope for a "tick" sound.
      @envelope.attack = 0.0
      @envelope.decay = 0.04
      @envelope.sustain = 0.0
      @envelope.release = 0.03

      # Higher cutoff frequency for hi-hat.
      @vcf.high_pass_cutoff = 5500.0

      @base_midi_note = 96
    end

    def note_on(midi_note, velocity)
      # Apply base MIDI note.
      actual_note = @base_midi_note

      new_note = Note.new
      new_note.set_by_midi(actual_note)
      new_note.phase = 0.0
      new_note.note_on_sample_index = @global_sample_count

      @active_notes[midi_note] = new_note
    end

    def note_off(midi_note)
      if @active_notes[midi_note]
        @active_notes[midi_note].note_off_sample_index = @global_sample_count
      end
    end

    def generate(buffer_size)
      start_sample_index = @global_sample_count
      samples = Array.new(buffer_size, 0.0)

      return samples if @active_notes.empty?

      @active_notes.each do |midi_note, note|
        note_on_index = note.note_on_sample_index
        time_since_note_on = (start_sample_index - note_on_index) / @sample_rate.to_f

        time_since_note_off = nil
        if note.note_off_sample_index
          time_since_note_off = (start_sample_index - note.note_off_sample_index) / @sample_rate.to_f
        end

        # Frequency ratios for the six oscillators of the 808 hi-hat (metallic harmonics).
        ratios = [1.0, 1.4, 1.7, 2.0, 2.5, 3.0]

        buffer_size.times do |i|
          current_time = time_since_note_on + (i / @sample_rate.to_f)

          # make a noise
          noise = 0.0
          ratios.each do |ratio|
            # Slightly detune to add thickness.
            detune = rand(-0.01..0.01)
            freq = note.frequency * ratio * (1.0 + detune)

            # Combine two phase-shifted square waves.
            square1 = (Math.sin(2.0 * Math::PI * freq * current_time) > 0) ? 1.0 : -1.0
            square2 = (Math.sin(2.0 * Math::PI * freq * (current_time + 0.5)) > 0) ? 1.0 : -1.0

            noise += (square1 + square2) * 0.5
          end

          noise /= ratios.length

          # Also add random noise.
          white_noise = rand(-0.3..0.3)  # Lower the noise level.
          noise = (noise * 0.8) + (white_noise * 0.2)  # Lower the white noise ratio.

          # Apply envelope.
          env_value = @envelope.at(current_time, time_since_note_off)

          # Pass through the high-pass filter (using VCF class).
          value = noise * env_value * @amplitude * 0.8  # Also slightly lower the overall volume.

          # Add to the sample.
          samples[i] += value
        end
      end

      samples = @vcf.process(samples, :high_pass)

      cleanup_inactive_notes(buffer_size)

      master_gain = 1.0
      samples.map! { |sample| sample * master_gain }

      @global_sample_count += buffer_size

      samples
    end

    private

    def cleanup_inactive_notes(buffer_size)
      current_time = @global_sample_count / @sample_rate.to_f
      buffer_duration = buffer_size / @sample_rate.to_f

      @active_notes.delete_if do |_, note|
        if note.note_off_sample_index
          time_since_note_off = current_time - (note.note_off_sample_index / @sample_rate.to_f)
          time_since_note_off > @envelope.release + buffer_duration
        else
          false
        end
      end
    end
  end
end
