require_relative "vcf"
require_relative "oscillator"
require_relative "envelope"
require_relative "note"

class Synthesizer
  attr_accessor :active, :envelope
  attr_reader :vcf

  def initialize(sample_rate, amplitude)
    @sample_rate = sample_rate
    @amplitude = amplitude
    @active_notes = {}
    @oscillator = Oscillator.new(:sawtooth, sample_rate)
    @vcf = VCF.new(sample_rate)
    @envelope = Envelope.new
    @global_sample_count = 0
  end

  def note_on(midi_note, velocity)
    # TODO: velocityで強弱を付けたい
    new_note = Note.new
    new_note.set_by_midi(midi_note)
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
    return Array.new(buffer_size, 0.0) if @active_notes.empty?

    # 個々の発音を合成する先
    samples = Array.new(buffer_size, 0.0)

    start_sample_index = @global_sample_count

    @active_notes.each_value do |note|
      wave = @oscillator.generate_wave(note, buffer_size)

      wave.each_with_index do |sample_val, idx|
        current_sample_index = start_sample_index + idx
        env_val = @envelope.apply_envelope(note, current_sample_index, @sample_rate)

        wave[idx] = sample_val * env_val
      end

      # 各ノートの波形を足し合わせるだけ
      samples = samples.zip(wave).map { |s1, s2| s1 + s2 }
    end

    # 固定のゲインをかける
    # TODO: VCA側で制御したい
    master_gain = 5.0
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
