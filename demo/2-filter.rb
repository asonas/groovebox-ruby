require 'unimidi'
require 'ffi-portaudio'
require_relative '../lib/groovebox'
require_relative '../lib/note'
require_relative '../lib/vca'
require_relative '../lib/synthesizer'

SAMPLE_RATE = 44100
BUFFER_SIZE = 128

# CC numbers for demo control
START_DEMO_CC = 40  # Start/stop auto demo
NEXT_DEMO_CC = 41   # Next demo section
PRESET_LPF_CC = 42  # Switch to LPF preset
PRESET_HPF_CC = 43  # Switch to HPF preset
PRESET_BPF_CC = 44  # Switch to Band Pass Filter preset
PRESET_RES_CC = 45  # Switch to Resonant preset

# Musical notes and scales
NOTES = {
  "C4" => 60, "C#4" => 61, "D4" => 62, "D#4" => 63, "E4" => 64, "F4" => 65,
  "F#4" => 66, "G4" => 67, "G#4" => 68, "A4" => 69, "A#4" => 70, "B4" => 71,
  "C5" => 72, "C#5" => 73, "D5" => 74, "D#5" => 75, "E5" => 76, "F5" => 77,
}

C_MAJOR_SCALE = %w[C4 D4 E4 F4 G4 A4 B4 C5]
C_MINOR_SCALE = ["C4", "D4", "D#4", "F4", "G4", "G#4", "A#4", "C5"]
CHROMATIC_SCALE = ["C4", "C#4", "D4", "D#4", "E4", "F4", "F#4", "G4", "G#4", "A4", "A#4", "B4", "C5"]

# Demo sequences
SEQUENCES = {
  "scale_up_down" => {
    name: "Major Scale Up & Down",
    notes: C_MAJOR_SCALE + C_MAJOR_SCALE.reverse[1..-1],
    note_duration: 0.2,
  },
  "chromatic" => {
    name: "Chromatic Scale",
    notes: CHROMATIC_SCALE,
    note_duration: 0.15,
  },
  "arpeggio" => {
    name: "C Major Arpeggio",
    notes: %w[C4 E4 G4 C5 G4 E4] * 3,
    note_duration: 0.15,
  },
  "bass_line" => {
    name: "Bass Line",
    notes: ["C3", "C3", "G3", "C3", "A#3", "C3", "G3", "C3"] * 2,
    note_duration: 0.2,
  },
}

# Filter presets to demonstrate
FILTER_PRESETS = {
    "no_filter" => {
    name: "No Filter (Raw Waveform)",
    type: nil,
    description: "",
  },

  "lpf_sweep" => {
    name: "Low Pass Filter Sweep",
    type: :low_pass,
    start_cutoff: 200,
    end_cutoff: 4000,
    resonance: 0.2,
    description: "",
  },
  "hpf_sweep" => {
    name: "High Pass Filter Sweep",
    type: :high_pass,
    start_cutoff: 100,
    end_cutoff: 2000,
    resonance: 0.2,
    description: "",
  },
  # "resonance_sweep" => {
  #   name: "Resonance Sweep (LPF)",
  #   type: :low_pass,
  #   cutoff: 1200,
  #   start_resonance: 0.0,
  #   end_resonance: 0.35,
  #   description: "レゾナンスはカットオフ付近の周波数を強調します。高いと自己発振します。",
  # },
  # "band_pass" => {
  #   name: "Band Pass Filter",
  #   type: :band_pass,
  #   cutoff: 400,
  #   resonance: 0.2,
  #   description: "",
  # },
}

class FilterShowcase
  attr_reader :groovebox, :synth, :current_demo, :auto_demo_running

  def initialize
    @groovebox = Groovebox.new
    @demo_thread = nil
    @auto_demo_running = false
    @current_sequence = SEQUENCES["scale_up_down"]
    @current_preset = FILTER_PRESETS["lpf_sweep"]
    @active_notes = {}

    # Create main synthesizer
    @synth = create_synth
    @groovebox.add_instrument(@synth)

    # Additional setup
    setup_audio_stream
  end

  def create_synth
    synth = Synthesizer.new(SAMPLE_RATE, 3000) # amplitudeを1500から3000に増やして音量アップ
    synth.oscillator.waveform = :sawtooth
    synth.vcf.low_pass_cutoff = 1000.0
    synth.vcf.high_pass_cutoff = 100.0
    synth.vcf.resonance = 0.2
    synth
  end

  def setup_audio_stream
    @stream = VCA.new(@groovebox, SAMPLE_RATE, BUFFER_SIZE)
  end

  def shutdown
    @auto_demo_running = false
    @stream.close if @stream
    @demo_thread&.join(1) # Wait for demo thread to finish
  end

  def toggle_auto_demo
    @auto_demo_running = !@auto_demo_running

    if @auto_demo_running
      puts "Starting auto demo..."
      start_auto_demo
    else
      puts "Stopping auto demo..."
      stop_auto_demo
    end
  end

  def start_auto_demo
    @demo_thread&.kill # Kill any existing demo

    @demo_thread = Thread.new do
      # Run through each filter preset with current sequence
      FILTER_PRESETS.each do |key, preset|
        break unless @auto_demo_running

        apply_filter_preset(preset)
        puts "\n=== #{preset[:name]} ==="
        puts preset[:description]
        play_sequence_with_filter(@current_sequence, preset)

        # Pause between presets
        sleep 1
      end

      @auto_demo_running = false
      puts "\nAuto demo completed."
    end
  end

  def stop_auto_demo
    @demo_thread&.kill
    @demo_thread = nil
    all_notes_off
  end

  def apply_filter_preset(preset)
    @current_preset = preset

    # フィルタータイプをシンセサイザーに設定
    @synth.filter_type = preset[:type]

    if preset[:type]
      # Set initial cutoff and resonance if provided
      @synth.vcf.low_pass_cutoff = preset[:cutoff] || preset[:start_cutoff] || 1000.0 if preset[:type] == :low_pass || preset[:type] == :band_pass
      @synth.vcf.high_pass_cutoff = preset[:cutoff] || preset[:start_cutoff] || 100.0 if preset[:type] == :high_pass || preset[:type] == :band_pass
      @synth.vcf.resonance = preset[:resonance] || preset[:start_resonance] || 0.2
    end
  end

  def play_sequence_with_filter(sequence, filter_preset)
    notes = sequence[:notes]
    duration = sequence[:note_duration]

    # Get sweep parameters if any
    has_cutoff_sweep = filter_preset[:start_cutoff] && filter_preset[:end_cutoff]
    has_resonance_sweep = filter_preset[:start_resonance] && filter_preset[:end_resonance]

    # Calculate step values for sweeps
    if has_cutoff_sweep
      cutoff_step = (filter_preset[:end_cutoff] - filter_preset[:start_cutoff]) / notes.length
      current_cutoff = filter_preset[:start_cutoff]
    end

    if has_resonance_sweep
      resonance_step = (filter_preset[:end_resonance] - filter_preset[:start_resonance]) / notes.length
      current_resonance = filter_preset[:start_resonance]
    end

    # Play each note in sequence
    notes.each_with_index do |note_name, idx|
      break unless @auto_demo_running

      midi_note = NOTES[note_name] || note_name.to_i

      # Update filter parameters if sweeping
      if has_cutoff_sweep
        if filter_preset[:type] == :low_pass || filter_preset[:type] == :band_pass
          @synth.vcf.low_pass_cutoff = current_cutoff
          puts "  LPF Cutoff: #{current_cutoff.round(2)} Hz" if idx % 4 == 0
        elsif filter_preset[:type] == :high_pass || filter_preset[:type] == :band_pass
          @synth.vcf.high_pass_cutoff = current_cutoff
          puts "  HPF Cutoff: #{current_cutoff.round(2)} Hz" if idx % 4 == 0
        end
        current_cutoff += cutoff_step
      end

      if has_resonance_sweep
        @synth.vcf.resonance = current_resonance
        puts "  Resonance: #{current_resonance.round(2)}" if idx % 4 == 0
        current_resonance += resonance_step
      end

      # Play the note
      @groovebox.sequencer_note_on(midi_note, 100)
      @active_notes[midi_note] = true

      # Hold the note for the specified duration
      sleep duration

      # Release the note
      @groovebox.sequencer_note_off(midi_note)
      @active_notes.delete(midi_note)

      # Small gap between notes (articulation)
      sleep 0.02
    end
  end

  def all_notes_off
    @active_notes.keys.each do |note|
      @groovebox.sequencer_note_off(note)
    end
    @active_notes = {}
  end

  def change_sequence(sequence_key)
    if SEQUENCES[sequence_key]
      @current_sequence = SEQUENCES[sequence_key]
      puts "Changed to sequence: #{@current_sequence[:name]}"
    end
  end

  def handle_midi_input(input)
    Thread.new do
      loop do
        m = input.gets

        m.each do |message|
          # Skip certain MIDI messages
          skip_midi_note = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
          next if message[:data][0] == 254 # Active Sensing
          next if skip_midi_note.include?(message[:data][1])

          data = message[:data]
          status_byte = data[0]

          case status_byte & 0xF0
          when 0x90 # Note On
            midi_note = data[1]
            velocity = data[2]

            if velocity > 0
              handle_note_on(midi_note, velocity)
            else
              handle_note_off(midi_note)
            end

          when 0x80 # Note Off
            midi_note = data[1]
            handle_note_off(midi_note)

          when 0xB0 # Control Change
            cc_number = data[1]
            cc_value = data[2]

            # Only process when value > 0 to avoid duplicate triggers
            if cc_value > 0
              handle_cc(cc_number, cc_value)
            end
          end
        end
      end
    end
  end

  def handle_note_on(midi_note, velocity)
    puts "Note On: #{midi_note}, Velocity: #{velocity}"

    # If auto demo is running, don't allow manual notes
    return if @auto_demo_running

    @groovebox.sequencer_note_on(midi_note, velocity)
    @active_notes[midi_note] = true
  end

  def handle_note_off(midi_note)
    puts "Note Off: #{midi_note}"

    # If auto demo is running, don't process manual note offs
    return if @auto_demo_running

    @groovebox.sequencer_note_off(midi_note)
    @active_notes.delete(midi_note)
  end

  def handle_cc(cc_number, cc_value)
    case cc_number
    when START_DEMO_CC
      toggle_auto_demo

    when NEXT_DEMO_CC
      # Cycle through sequences
      keys = SEQUENCES.keys
      current_idx = keys.index(@current_sequence.is_a?(Hash) ? keys.find { |k| SEQUENCES[k] == @current_sequence } : nil) || 0
      next_idx = (current_idx + 1) % keys.size
      change_sequence(keys[next_idx])

    when PRESET_LPF_CC
      apply_filter_preset(FILTER_PRESETS["lpf_sweep"])
      puts "Switched to #{@current_preset[:name]}"
      puts @current_preset[:description]

    when PRESET_HPF_CC
      apply_filter_preset(FILTER_PRESETS["hpf_sweep"])
      puts "Switched to #{@current_preset[:name]}"
      puts @current_preset[:description]

    when PRESET_BPF_CC
      apply_filter_preset(FILTER_PRESETS["band_pass"])
      puts "Switched to #{@current_preset[:name]}"
      puts @current_preset[:description]

    when PRESET_RES_CC
      apply_filter_preset(FILTER_PRESETS["resonance_sweep"])
      puts "Switched to #{@current_preset[:name]}"
      puts @current_preset[:description]
    end
  end

  def display_help
    puts "\nFilter Showcase - Interactive Filter Demo"
    puts "=========================================="
    puts "CC #{START_DEMO_CC}: Start/Stop auto demo sequence"
    puts "CC #{NEXT_DEMO_CC}: Change demo sequence"
    puts "\nFilter Presets:"
    puts "CC #{PRESET_LPF_CC}: Low Pass Filter Sweep"
    puts "CC #{PRESET_HPF_CC}: High Pass Filter Sweep"
    puts "CC #{PRESET_BPF_CC}: Band Pass Filter"
    puts "CC #{PRESET_RES_CC}: Resonance Sweep"
    puts "\nPlay notes to hear the current filter setting"
    puts "Press Ctrl+C to exit"

    # Display current settings
    puts "\nCurrent Settings:"
    puts "Filter: #{@current_preset[:name]}"
    puts "Sequence: #{@current_sequence[:name]}"
    puts "\nStart the auto demo to hear filter effects!"
  end
end

# Main program
begin
  FFI::PortAudio::API.Pa_Initialize

  puts "Filter Showcase - Interactive Demo"
  puts "=================================="
  puts "スケールアップ・ダウンを自動再生します..."

  # MIDI入力は使用せず、自動デモを開始
  # input = UniMIDI::Input.gets
  # puts "Using: #{input.name}"

  # Create and start the showcase
  showcase = FilterShowcase.new
  # showcase.display_help

  # 自動再生を開始
  showcase.toggle_auto_demo

  # デモが終わるまで待機し、終了したらプログラムも終了する
  sleep 0.5 while showcase.auto_demo_running


  # Keep the main thread alive
  # loop { sleep 1 }

rescue Interrupt
  puts "\nExiting..."
  showcase&.shutdown
  # input&.close
  FFI::PortAudio::API.Pa_Terminate
end
