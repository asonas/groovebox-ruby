module Presets
  class Piano < Synthesizer
    attr_accessor :base_note
    attr_accessor :filter_cutoff, :filter_resonance
    attr_accessor :brightness, :hardness
    attr_accessor :oscillators, :oscillator_mix

    def initialize(sample_rate = 44100, amplitude = 1000)
      super(sample_rate, amplitude)

      # Piano-like ADSR envelope settings.
      # Fast attack, medium decay, low sustain, long release.
      @envelope.attack = 0.001  # Very fast attack.
      @envelope.decay = 0.8     # Relatively long decay.
      @envelope.sustain = 0.2   # Low sustain level.
      @envelope.release = 0.5   # Long release.

      # Main oscillator (inherited from parent class) settings.
      @oscillator.waveform = :triangle

      # Reproduce the harmonic structure of the main oscillator.
      @oscillator.harmonics = [
        [1.0, 1.0],    # Fundamental (100%).
        [2.0, 0.5],    # 2nd harmonic (50%).
        [3.0, 0.3],    # 3rd harmonic (30%).
        [4.0, 0.2],    # 4th harmonic (20%).
        [5.0, 0.1],    # 5th harmonic (10%).
        [6.0, 0.05],   # 6th harmonic (5%).
        [7.0, 0.025],  # 7th harmonic (2.5%).
      ]

      # Create additional oscillators (for sound thickness).
      @oscillators = []

      # Oscillator 1: Slightly different waveform characteristics and slightly detuned.
      osc1 = Oscillator.new(:sine, sample_rate)
      osc1.harmonics = [
        [1.0, 0.8],  # Fundamental (80%).
        [2.0, 0.4],  # 2nd harmonic (40%).
        [3.0, 0.2],  # 3rd harmonic (20%).
      ]
      @oscillators << osc1

      # Oscillator 2: Soft-sounding pulse wave (detuned).
      osc2 = Oscillator.new(:pulse, sample_rate)
      osc2.harmonics = [
        [1.0, 0.3],    # Fundamental (30% - subtle).
        [2.0, 0.1],    # 2nd harmonic (10%).
      ]
      @oscillators << osc2

      # Oscillator mix ratio [Main, Oscillator 1, Oscillator 2].
      # Note: If the sum exceeds 1.0, the volume might become too high.
      @oscillator_mix = [0.6, 0.25, 0.15]

      # Detune values (in cents - 100 cents = 1 semitone).
      @detune_cents = [0, 5, -7]  # Main, Oscillator 1, Oscillator 2.

      # Filter settings.
      @vcf.low_pass_cutoff = 5000.0  # Higher cutoff.
      @vcf.high_pass_cutoff = 100.0  # Allows some low frequencies through.

      # Accessible parameters.
      @filter_cutoff = 5000.0
      @filter_resonance = 0.1  # Subtle resonance.

      # Piano tone adjustment parameters.
      @brightness = 0.7  # Brightness (0.0-1.0).
      @hardness = 0.5    # Hardness (0.0-1.0).

      # Base note (C3 = Middle C).
      @base_note = Note.new.set_by_midi(24)
    end

    # @param midi_note [Integer]
    # @param velocity [Integer]
    # @param midi_note [Integer]
    # @param velocity [Integer]
    def note_on(midi_note, velocity)
      new_note = Note.new
      semitone_diff = midi_note - @base_note.midi_note
      new_note.set_by_midi(semitone_diff)

      new_note.phase = 0.0
      new_note.note_on_sample_index = @global_sample_count

      # Reproduce the behavior where the timbre changes based on velocity (strength).
      vel_normalized = velocity / 127.0
      new_note.velocity = vel_normalized

      # Dynamically adjust the envelope and timbre according to velocity.
      # The harder you play, the faster the attack and the longer the decay.
      dynamic_attack = @envelope.attack * (1.0 - (vel_normalized * 0.3))
      dynamic_decay = @envelope.decay * (1.0 + (vel_normalized * 0.5))

      # Create and adjust a copy of the envelope for each note.
      new_note.custom_envelope = @envelope.dup
      new_note.custom_envelope.attack = dynamic_attack
      new_note.custom_envelope.decay = dynamic_decay

      # Adjust filter cutoff according to velocity.
      # The harder you play, the brighter the sound.
      new_note.filter_cutoff = @filter_cutoff * (1.0 + (vel_normalized * @brightness))

      @active_notes[midi_note] = new_note

      note_name = new_note.name + new_note.octave.to_s
      puts "piano note_on: midi_note=#{midi_note} (#{note_name}), velocity=#{velocity}, frequency=#{new_note.frequency.round(2)}Hz"
    end

    def generate(buffer_size)
      return Array.new(buffer_size, 0.0) if @active_notes.empty?

      samples = Array.new(buffer_size, 0.0)

      start_sample_index = @global_sample_count
      active_note_count = 0

      @active_notes.each_value do |note|
        # Generate waveform for the main oscillator.
        main_wave = @oscillator.generate_wave(note, buffer_size)

        # Generate waveforms for additional oscillators.
        additional_waves = []

        @oscillators.each_with_index do |osc, idx|
          # Create a temporary note for detuning.
          detuned_note = note.dup

          # Apply detuning (convert cent value to pitch ratio).
          if @detune_cents[idx + 1] != 0
            cent_ratio = 2.0 ** (@detune_cents[idx + 1] / 1200.0)
            detuned_freq = note.frequency * cent_ratio

            # Adjust only the frequency (phase, etc., remain the same as the original note).
            class << detuned_note
              attr_accessor :detuned_frequency
              alias_method :original_frequency, :frequency

              def frequency
                @detuned_frequency || original_frequency
              end
            end

            detuned_note.detuned_frequency = detuned_freq
          end

          # Generate waveform with the detuned note.
          additional_waves << osc.generate_wave(detuned_note, buffer_size)
        end

        # Apply envelope to all waveforms.
        all_waves = [main_wave] + additional_waves

        all_waves.each_with_index do |wave, wave_idx|
          wave.each_with_index do |sample_val, idx|
            current_sample_index = start_sample_index + idx
            env_val =
              if note.custom_envelope
                note.custom_envelope.apply_envelope(note, current_sample_index, @sample_rate)
              else
                @envelope.apply_envelope(note, current_sample_index, @sample_rate)
              end

            # Apply the appropriate mix ratio.
            wave[idx] = sample_val * env_val * @oscillator_mix[wave_idx]
          end
        end

        # Combine all waveforms.
        combined_wave = Array.new(buffer_size, 0.0)
        all_waves.each do |wave|
          combined_wave = combined_wave.zip(wave).map { |s1, s2| s1 + s2 }
        end

        # Apply note-specific filter cutoff.
        @vcf.resonance = @filter_resonance
        filter_cutoff = note.filter_cutoff || @filter_cutoff
        @vcf.low_pass_cutoff = filter_cutoff
        combined_wave = @vcf.process(combined_wave, :low_pass)

        # For high-range keys, additional filtering to emphasize high frequencies.
        if note.midi_note > 80  # If in the high range.
          high_emphasis = 1.0 + ((note.midi_note - 80) * 0.02)  # Emphasize more as the pitch gets higher.
          combined_wave.map! { |s| s * high_emphasis }
        end

        # For low-range keys, emphasize low frequencies.
        if note.midi_note < 48
          low_emphasis = 1.0 + ((48 - note.midi_note) * 0.03) # Emphasize more as the pitch gets lower.
          combined_wave.map! { |s| s * low_emphasis }
        end

        samples = samples.zip(combined_wave).map { |s1, s2| s1 + s2 }
        has_sound = combined_wave.any? { |sample| sample != 0.0 }
        active_note_count += 1 if has_sound
      end

      master_gain = 2.0
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
          env = note.custom_envelope || @envelope
          final_env = env.apply_envelope(note, @global_sample_count - 1, @sample_rate)
          final_env <= 0.0
        else
          false
        end
      end
    end
  end
end
