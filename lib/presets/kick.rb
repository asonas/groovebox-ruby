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

      # Since it's a drum kick, the pitch is always fixed. Ignore midi_note.
      new_note.set_by_midi(@base_note.midi_note)
      new_note.phase = 0.0
      new_note.note_on_sample_index = @global_sample_count


      @active_notes[midi_note] = new_note
      puts "kick note_on: #{midi_note}, velocity=#{velocity}"
    end

    def note_off(midi_note)
      super(midi_note)
    end

    # Implement pitch bend.
    def generate(buffer_size)
      start_sample_index = @global_sample_count
      samples = Array.new(buffer_size, 0.0)

      @active_notes.each_value do |note|
        pitch_env_duration = 0.05 # Drops rapidly around 50ms.
        pitch_ratio = 20.0        # Relative ratio when the pitch is highest.

        wave = @oscillator.generate_wave(note, buffer_size)

        wave.each_with_index do |sample_val, idx|
          current_sample_index = start_sample_index + idx
          time_sec = (current_sample_index - note.note_on_sample_index).to_f / @sample_rate

          # Pitch envelope: Until time_sec reaches pitch_env_duration,
          # assume it exponentially approaches 1.0 from pitch_ratio.
          if time_sec < pitch_env_duration
            t = time_sec / pitch_env_duration
            # Calculation: starts at pitch_ratio times -> approaches 1.0 times at the end.
            current_pitch_multiplier = 1.0 + (pitch_ratio - 1.0) * (1.0 - t)
          else
            current_pitch_multiplier = 1.0
          end

          # Apply pitch correction.
          sample_val *= current_pitch_multiplier

          # Apply Envelope.
          env_val = @envelope.apply_envelope(note, current_sample_index, @sample_rate)
          wave[idx] = sample_val * env_val
        end

        # Add the waveforms of each note together.
        samples = samples.zip(wave).map { |s1, s2| s1 + s2 }
      end

      master_gain = 20.0
      samples.map! { |sample| sample * master_gain }

      @global_sample_count += buffer_size
      cleanup_inactive_notes(buffer_size)

      samples
    end
  end
end
