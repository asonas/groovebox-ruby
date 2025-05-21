require 'io/console'
require 'ffi-portaudio'
require 'drb/drb'
require 'midilib'

SAMPLE_RATE = 44100
BUFFER_SIZE = 128


require_relative "groovebox"
require_relative "drum_rack"
require_relative "synthesizer"
require_relative "note"
require_relative "vca"
require_relative "step"

require_relative "presets/bass"
require_relative "presets/kick"
require_relative "presets/snare"
require_relative "presets/hihat_closed"
require_relative "presets/piano"
require_relative "sidechain"

require_relative "periodic_cue"

class Sequencer
  attr_reader :tracks, :steps_per_track

  DEFAULT_NOTES = ["C3", "C#3", "D3", "D#3", "E3", "F3", "F#3", "G3", "G#3", "A3", "A#3", "B3",
                  "C4", "C#4", "D4", "D#4", "E4", "F4", "F#4", "G4", "G#4", "A4", "A#4", "B4",]

  NOTE_TO_MIDI = {}
  DEFAULT_NOTES.each_with_index do |note_name, idx|
    NOTE_TO_MIDI[note_name] = 48 + idx
  end

  def initialize(groovebox = nil, mid_file_path = nil)
    @groovebox = groovebox
    @current_position = 0
    @current_track = 0
    @current_voice = 0
    @steps_per_track = 32
    @tracks = []
    @playing = false
    @bpm = 120

    initialize_tracks

    if mid_file_path
      puts "Loading MIDI file: #{mid_file_path}"
      load_midi_file(mid_file_path)
    end
  end

  def initialize_tracks
    return if @groovebox.nil?

    @instruments = @groovebox.instruments

    @instruments.each_with_index do |instrument, idx|
      track_name = "Track #{idx}"

      if instrument.respond_to?(:pad_notes)
        instrument.pad_notes.sort.each do |pad_note|
          track = Array.new(@steps_per_track) { Step.new }
          @tracks << {
            name: "Drum #{pad_note}",
            instrument_index: idx,
            midi_note: pad_note,
            steps: track,
            polyphony: 1,
            voices: [0],
          }
        end
      else
        polyphony = @groovebox.polyphony(idx)
        voices = (0...polyphony).to_a

        poly_steps = voices.map { Array.new(@steps_per_track) { Step.new } }

        @tracks << {
          name: track_name,
          instrument_index: idx,
          midi_note: nil,
          steps: poly_steps,
          polyphony: polyphony,
          voices: voices,
        }
      end
    end

    if @tracks.empty?
      @tracks = [
        {
          name: "Default Track",
          instrument_index: 0,
          midi_note: nil,
          steps: [Array.new(@steps_per_track) { Step.new }],
          polyphony: 1,
          voices: [0],
        },
      ]
    end
  end

  def load_midi_file(midi_file_path)
    seq = MIDI::Sequence.new

    File.open(midi_file_path, 'rb') do |file|
      seq.read(file)
    end

    puts "Loaded #{seq.tracks.size} tracks"

    # Initialize tracks
    @tracks.each do |track_info|
      if track_info[:midi_note]
        # Drum track
        track_info[:steps].each do |step|
          step.active = false
          step.note = nil
          step.velocity = nil
        end
      else
        # Synth track
        track_info[:steps].each do |voice_steps|
          voice_steps.each do |step|
            step.active = false
            step.note = nil
            step.velocity = nil
          end
        end
      end
    end

    # Find BPM from tempo events
    seq.tracks.each do |track|
      tempo_events = track.events.select { |e| e.kind_of?(MIDI::Tempo) }
      if tempo_events.any?
        tempo_event = tempo_events.first
        @bpm = 60_000_000 / tempo_event.tempo
        break
      end
    end

    # See if we have any drum tracks to map to
    synth_tracks = @tracks.select { |t| t[:midi_note].nil? }
    drum_tracks = @tracks.select { |t| t[:midi_note] }

    # Skip the first track (usually just tempo/timing info)
    seq.tracks.each_with_index do |midi_track, track_index|
      next if track_index == 0

      puts "MIDI Track #{track_index}: #{midi_track.name}"

      # Find all note-on events with velocity > 0
      note_on_events = midi_track.events.select do |event|
        event.kind_of?(MIDI::NoteOn) && event.velocity > 0
      end

      # Skip tracks with no notes
      next if note_on_events.empty?

      # Detect if this is a drum track (MIDI channel 10)
      channel = note_on_events.first.channel if note_on_events.first.respond_to?(:channel)
      is_drum_track = channel == 9

      # Count occurrences of each note
      note_counts = Hash.new(0)
      note_on_events.each { |event| note_counts[event.note] += 1 }

      puts "  Note distribution: #{note_counts.inspect}"
      puts "  Channel: #{channel}, Drum track: #{is_drum_track}"

      ticks_per_step = seq.ppqn / 4.0  # Ticks per 16th note

      if is_drum_track
        # For drum tracks, find the corresponding drum track for each note
        note_counts.each do |note_num, count|
          # Find drum track matching this note
          matching_drum_track = drum_tracks.find { |dt| dt[:midi_note].to_i == note_num }

          # Skip if no matching drum track found
          next unless matching_drum_track

          puts "  Assigning drum note #{note_num} to track #{matching_drum_track[:name]}"

          # Extract events only for this drum note
          drum_events = note_on_events.select { |event| event.note == note_num }

          # Set steps
          drum_events.each do |event|
            step_index = (event.time_from_start / ticks_per_step).to_i
            next if step_index >= @steps_per_track

            puts "    Setting drum note at step #{step_index + 1}"

            matching_drum_track[:steps][step_index].active = true
            matching_drum_track[:steps][step_index].note = note_num.to_s
            matching_drum_track[:steps][step_index].velocity = event.velocity
          end
        end
      else
        # For synth tracks, use the next available synth track
        target_track = synth_tracks.first
        synth_tracks.shift  # Remove the used track

        # Skip if no synth tracks available
        next unless target_track

        puts "  Assigning synth notes to track #{target_track[:name]}"

        step_notes = {}
        note_on_events.each do |event|
          step_index = (event.time_from_start / ticks_per_step).to_i
          next if step_index >= @steps_per_track

          step_notes[step_index] ||= []
          step_notes[step_index] << event
        end

        step_notes.each do |step_index, events|
          notes_count = events.size

          available_voices = [notes_count, target_track[:polyphony]].min

          events.each_with_index do |event, note_index|
            voice_index = note_index % available_voices

            note_obj = Note.new.set_by_midi(event.note)
            note_name = "#{note_obj.name}#{note_obj.octave}"

            puts "    Setting note #{note_name} at step #{step_index + 1} on voice #{voice_index + 1}"

            target_step = target_track[:steps][voice_index][step_index]
            target_step.active = true
            target_step.note = note_name
            target_step.velocity = event.velocity
          end
        end
      end
    end

    # Initialize after loading from MIDI file
    @current_position = 0
  end

  def toggle_step(track_index, step_index, voice_index = 0)
    track = @tracks[track_index]

    # Drum track
    if track[:midi_note]
      step = track[:steps][step_index]
      step.active = !step.active
    else
      # Synth track
      voice_index = [voice_index, track[:polyphony] - 1].min
      step = track[:steps][voice_index][step_index]
      step.active = !step.active

      if step.active && step.note.nil?
        step.note = "C4"
      end
    end
  end

  # Transpose note up by one semitone
  def transpose_note_up(track_index, step_index, voice_index = 0)
    track = @tracks[track_index]

    step =
      if track[:midi_note]
        track[:steps][step_index]
      else
        track[:steps][voice_index][step_index]
      end

    return unless step && step.active && step.note

    note = Note.new.set_by_name(step.note)

    new_midi_note = note.midi_note + 1
    return if new_midi_note > 127  # Check maximum value

    new_note = Note.new.set_by_midi(new_midi_note)

    step.note = "#{new_note.name}#{new_note.octave}"
  end

  # Transpose note down by one semitone
  def transpose_note_down(track_index, step_index, voice_index = 0)
    track = @tracks[track_index]

    step =
      if track[:midi_note]
        track[:steps][step_index]
      else
        track[:steps][voice_index][step_index]
      end

    return unless step && step.active && step.note

    note = Note.new.set_by_name(step.note)

    new_midi_note = note.midi_note - 1
    return if new_midi_note < 0  # Check minimum value

    new_note = Note.new.set_by_midi(new_midi_note)

    step.note = "#{new_note.name}#{new_note.octave}"
  end

  # Transpose note up by one octave
  def transpose_octave_up(track_index, step_index, voice_index = 0)
    track = @tracks[track_index]

    step =
      if track[:midi_note]
        track[:steps][step_index]
      else
        track[:steps][voice_index][step_index]
      end

    return unless step && step.active && step.note

    note = Note.new.set_by_name(step.note)

    new_midi_note = note.midi_note + 12
    return if new_midi_note > 127  # Check maximum value

    new_note = Note.new.set_by_midi(new_midi_note)

    step.note = "#{new_note.name}#{new_note.octave}"
  end

  # Transpose note down by one octave
  def transpose_octave_down(track_index, step_index, voice_index = 0)
    track = @tracks[track_index]

    step =
      if track[:midi_note]
        track[:steps][step_index]
      else
        track[:steps][voice_index][step_index]
      end

    return unless step && step.active && step.note

    note = Note.new.set_by_name(step.note)

    new_midi_note = note.midi_note - 12
    return if new_midi_note < 0  # Check minimum value

    new_note = Note.new.set_by_midi(new_midi_note)

    step.note = "#{new_note.name}#{new_note.octave}"
  end

  def display
    system('clear')
    puts "Groovebox Sequencer" + (@playing ? " (Playing)" : "")
    puts "==================="

    # ステップの番号を表示
    print "            "
    puts (1..@steps_per_track).map { |n| n.to_s.rjust(4) }.join

    # 各トラックと声部のステップを表示
    @tracks.each_with_index do |track_info, track_idx|
      if track_info[:midi_note] || track_info[:polyphony] == 1
        track_name = track_info[:name][0..8]

        if track_idx == @current_track && @current_voice == 0
          print "→ #{track_name.ljust(10)} "
        else
          print "  #{track_name.ljust(10)} "
        end

        steps = track_info[:midi_note] ? track_info[:steps] : track_info[:steps][0]
        puts display_steps(steps, track_info, track_idx, 0)
      else
        base_name = track_info[:name][0..6]

        # 各声部を表示
        track_info[:voices].each_with_index do |voice, voice_idx|
          voice_name = "#{base_name} V#{voice_idx + 1}"

          if track_idx == @current_track && voice_idx == @current_voice
            print "→ #{voice_name.ljust(9)} "
          else
            print "  #{voice_name.ljust(9)} "
          end

          steps = track_info[:steps][voice_idx]
          puts display_steps(steps, track_info, track_idx, voice_idx)
        end
      end
    end

    puts "\nCommands:"
    puts "  Space: Play/Stop"
    puts "  Arrow keys: Move cursor"
    puts "  Tab: Switch voice (for polyphonic tracks)"
    puts "  Enter: Toggle step"
    puts "  H/L: Transpose note down/up"
    puts "  Y/O: Transpose octave down/up"
    puts "  s: Save as MIDI file (format: yyyy-mm-dd-hh-mm-ss.mid)"
    puts "  Ctrl+C: Exit"
  end

  def display_steps(steps, track_info, track_idx, voice_idx)
    is_drum = track_info[:midi_note] != nil

    steps.map.with_index { |step, step_idx|
      step_display =
        if is_drum
          step.active ? "xx" : "__"
        else
          step.note && step.active ? step.note[0..1] : "__"
        end

      if track_idx == @current_track && voice_idx == @current_voice && step_idx == @current_position
        if step.active
          "[#{step_display}]"
        else
          "[__]"
        end
      else
        step.active ? " #{step_display} " : " __ "
      end
    }.join
  end

  def play_sequence
    return unless @groovebox

    if @playing
      @playing = false
      all_notes_off
      return
    end

    @playing = true
    puts "BPM: #{@bpm}"

    Thread.new do
      step_interval = 60.0 / @bpm / 4
      cue = PeriodicCue.new(step_interval * 0.8, step_interval * 0.2)

      play_position = 0

      cue.start
      while @playing
        @tracks.each do |track_info|
          instrument_index = track_info[:instrument_index]
          @groovebox.change_sequencer_channel(instrument_index)

          if track_info[:midi_note]
            # ドラムトラックの場合
            step = track_info[:steps][play_position]

            if step.active
              begin
                midi_note = track_info[:midi_note]
                velocity = step.velocity || 100
                @groovebox.sequencer_note_on(midi_note, velocity)
              rescue => e
                puts "error drum: #{e.message}"
              end
            end
          else
            # シンセサイザートラックの場合
            # 全ての声部をチェック
            track_info[:voices].each_with_index do |voice, voice_idx|
              step =
                if track_info[:polyphony] == 1
                  track_info[:steps][0][play_position]  # 単音の場合も最初の声部配列から取得
                else
                  track_info[:steps][voice_idx][play_position]
                end

              if step && step.active
                begin
                  note_obj = Note.new.set_by_name(step.note)
                  velocity = step.velocity || 100
                  @groovebox.sequencer_note_on(note_obj.midi_note, velocity)
                rescue => e
                  puts "error synth: #{e.message}"
                end
              end
            end
          end
        end

        # 少し待ってノートをオフにする
        cue.sync

        # ノートをオフにする
        @tracks.each do |track_info|
          instrument_index = track_info[:instrument_index]
          @groovebox.change_sequencer_channel(instrument_index)

          if track_info[:midi_note]
            # ドラムトラックの場合
            step = track_info[:steps][play_position]

            if step.active
              begin
                midi_note = track_info[:midi_note]
                @groovebox.sequencer_note_off(midi_note)
              rescue => e
                puts "error drum: #{e.message}"
              end
            end
          else
            # シンセサイザートラックの場合
            # 全ての声部をチェック
            track_info[:voices].each_with_index do |voice, voice_idx|
              step =
                if track_info[:polyphony] == 1
                  track_info[:steps][0][play_position]  # 単音の場合も最初の声部配列から取得
                else
                  track_info[:steps][voice_idx][play_position]
                end

              if step && step.active
                begin
                  note_obj = Note.new.set_by_name(step.note)
                  @groovebox.sequencer_note_off(note_obj.midi_note)
                rescue => e
                  puts "error synth: #{e.message}"
                end
              end
            end
          end
        end

        cue.sync

        play_position = (play_position + 1) % @steps_per_track
      end
    end
  end

  def all_notes_off
    return unless @groovebox

    # 各トラックに対して処理
    @tracks.each do |track_info|
      instrument_index = track_info[:instrument_index]
      @groovebox.change_sequencer_channel(instrument_index)

      if track_info[:midi_note].nil?
        # シンセサイザーやベースなどの場合
        # すべてのMIDIノート（0-127）に対してnote_offを送信
        (0..127).each do |midi_note|
          @groovebox.sequencer_note_off(midi_note)
        end
      else
        # DrumRackのパッドの場合
        midi_note = track_info[:midi_note]
        @groovebox.sequencer_note_off(midi_note)
      end
    end

    puts "all notes off"
  end

  def save_to_midi_file
    # MIDIシーケンスの作成
    seq = MIDI::Sequence.new
    # テンポの設定
    seq.ppqn = 480  # Pulses Per Quarter Note (四分音符あたりのティック数)

    # テンポトラックの作成
    tempo_track = MIDI::Track.new(seq)
    seq.tracks << tempo_track
    tempo_track.name = "Tempo Track"

    # テンポイベントの追加
    tempo_event = MIDI::Tempo.new(tempo_track)
    tempo_event.tempo = 60_000_000 / @bpm  # マイクロ秒/四分音符でテンポを指定
    tempo_track.events << tempo_event
    tempo_track.events << MIDI::MetaEvent.new(MIDI::META_TRACK_END, nil, 0)

    # デバッグ情報
    puts "Saving steps:"

    # 各トラックを処理
    @tracks.each_with_index do |track_info, track_idx|
      track_type = track_info[:midi_note].nil? ? "Synth" : "Drum"
      track_name = track_info[:name]

      # MIDIトラック作成
      midi_track = MIDI::Track.new(seq)
      seq.tracks << midi_track
      midi_track.name = track_name

      # チャンネル設定
      channel = track_info[:midi_note].nil? ? 0 : 9  # シンセなら0、ドラムなら9(チャンネル10)

      # プログラムチェンジ設定
      prog_num = track_info[:instrument_index] % 128
      prog_chg = MIDI::ProgramChange.new(channel, prog_num)
      midi_track.events << prog_chg

      # ステップデータの追加
      ticks_per_step = seq.ppqn / 4.0  # 16分音符あたりのティック数

      # アクティブなステップを処理
      if track_info[:midi_note]
        # ドラムトラックの場合
        steps = track_info[:steps]
        process_steps_for_midi(seq, midi_track, steps, track_info, channel, ticks_per_step)
      elsif track_info[:polyphony] == 1
        # 単音シンセの場合は最初の声部のみ
        steps = track_info[:steps][0]
        process_steps_for_midi(seq, midi_track, steps, track_info, channel, ticks_per_step)
      else
        # 複数の声部を持つシンセの場合
        track_info[:voices].each_with_index do |voice, voice_idx|
          steps = track_info[:steps][voice_idx]
          process_steps_for_midi(seq, midi_track, steps, track_info, channel, ticks_per_step)
        end
      end

      # トラックの終了イベント
      midi_track.events << MIDI::MetaEvent.new(MIDI::META_TRACK_END, nil, 0)
    end

    # 現在の日時を使ってファイル名を生成
    timestamp = Time.now.strftime("%Y-%m-%d-%H-%M-%S")
    filename = "#{timestamp}.mid"

    # イベントをソート
    seq.tracks.each do |track|
      track.recalc_delta_from_times
    end

    # MIDIファイルを保存
    File.open(filename, 'wb') do |file|
      seq.write(file)
    end

    puts "MIDI file saved: #{filename}"
    sleep 1  # Short pause to display message
    true
  end

  # MIDIファイル保存用にステップを処理するヘルパーメソッド
  def process_steps_for_midi(seq, midi_track, steps, track_info, channel, ticks_per_step)
    last_time = 0  # 前回のタイムスタンプを記録

    # アクティブなステップだけを処理するためにソート
    active_step_indices = []
    steps.each_with_index do |step, idx|
      active_step_indices << idx if step.active
    end

    puts "  Track: #{track_info[:name]} - Active steps: #{active_step_indices.size}"

    # ステップインデックスでソートして処理
    active_step_indices.sort.each do |step_idx|
      step = steps[step_idx]

      # ノートが有効か確認
      next unless step.note

      # ノートの開始位置（ティック単位）
      start_time = (step_idx * ticks_per_step).to_i

      # ノートの長さ（ティック単位） - 16分音符の長さ
      duration = (ticks_per_step * 0.95).to_i

      # MIDI番号への変換
      midi_note = nil
      if track_info[:midi_note].nil?
        # シンセサイザーの場合、ノート名からMIDIノート番号に変換
        begin
          note_obj = Note.new.set_by_name(step.note)
          midi_note = note_obj.midi_note
          puts "  Step #{step_idx + 1}: Note #{step.note} (MIDI: #{midi_note})"
        rescue => e
          puts "Warning: Failed to convert note '#{step.note}': #{e.message}"
          next
        end
      else
        midi_note = track_info[:midi_note].to_i
        puts "  Step #{step_idx + 1}: Drum pad #{midi_note}"
      end

      velocity = step.velocity || 100

      note_on = MIDI::NoteOn.new(channel, midi_note, velocity)
      note_on.time_from_start = start_time
      midi_track.events << note_on

      note_off = MIDI::NoteOff.new(channel, midi_note, 0)
      note_off.time_from_start = start_time + duration
      midi_track.events << note_off
    end
  end

  def run
    return puts "Groovebox is not connected" unless @groovebox

    # Initialize if tracks are empty
    initialize_tracks if @tracks.empty?

    loop do
      display
      key = STDIN.getch

      current_track_info = @tracks[@current_track] if @current_track < @tracks.size

      # if current_track_info
      #   if current_track_info[:midi_note]
      #     current_step = current_track_info[:steps][@current_position]
      #   elsif current_track_info[:polyphony] == 1
      #     current_step = current_track_info[:steps][0][@current_position]
      #   else
      #     current_step = current_track_info[:steps][@current_voice][@current_position]
      #   end
      # end

      case key
      when "\e"
        next_key = STDIN.getch
        if next_key == "["
          case STDIN.getch
          when "D"
            @current_position -= 1 if @current_position > 0
          when "C"
            @current_position += 1 if @current_position < @steps_per_track - 1
          when "A"
            if @current_voice > 0 && current_track_info && current_track_info[:polyphony] > 1
              @current_voice -= 1
            else
              @current_track -= 1 if @current_track > 0
              if @current_track >= 0 && @tracks[@current_track]
                @current_voice = [@tracks[@current_track][:polyphony] - 1, 0].max
              end
            end
          when "B"
            if current_track_info &&
               current_track_info[:polyphony] > 1 &&
               @current_voice < current_track_info[:polyphony] - 1
              @current_voice += 1
            else
              @current_track += 1 if @current_track < @tracks.size - 1
              @current_voice = 0
            end
          end
        end
      when "\t" # Tab
        if current_track_info && current_track_info[:polyphony] > 1
          @current_voice = (@current_voice + 1) % current_track_info[:polyphony]
        end
      when "\r" # Enter
        toggle_step(@current_track, @current_position, @current_voice)
      when "h", "H" # 一音下げる
        unless current_track_info && current_track_info[:midi_note]
          transpose_note_down(@current_track, @current_position, @current_voice)
        end
      when "l", "L" # 一音上げる
        unless current_track_info && current_track_info[:midi_note]
          transpose_note_up(@current_track, @current_position, @current_voice)
        end
      when "y", "Y" # 一オクターブ下げる
        unless current_track_info && current_track_info[:midi_note]
          transpose_octave_down(@current_track, @current_position, @current_voice)
        end
      when "o", "O" # 一オクターブ上げる
        unless current_track_info && current_track_info[:midi_note]
          transpose_octave_up(@current_track, @current_position, @current_voice)
        end
      when " " # スペース
        play_sequence
      when "s", "S"
        save_to_midi_file
      when "\u0003"
        @playing = false
        all_notes_off
        puts "exiting..."
        break
      end
    end
  end
end
