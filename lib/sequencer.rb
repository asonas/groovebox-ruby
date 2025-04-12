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
          @tracks << { name: "Drum #{pad_note}", instrument_index: idx, midi_note: pad_note, steps: track }
        end
      else
        track = Array.new(@steps_per_track) { Step.new }
        @tracks << { name: track_name, instrument_index: idx, midi_note: nil, steps: track }
      end
    end

    if @tracks.empty?
      @tracks = [
        {
          name: "Default Track",
          instrument_index: 0,
          midi_note: nil,
          steps: Array.new(@steps_per_track) { Step.new },
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

    @tracks.each do |track_info|
      track_info[:steps].each do |step|
        step.active = false
        step.note = nil
        step.velocity = nil
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

        # Set steps
        note_on_events.each do |event|
          step_index = (event.time_from_start / ticks_per_step).to_i
          next if step_index >= @steps_per_track

          # Convert note number to note name
          note_obj = Note.new.set_by_midi(event.note)
          note_name = "#{note_obj.name}#{note_obj.octave}"

          puts "    Setting note #{note_name} at step #{step_index + 1}"

          target_step = target_track[:steps][step_index]
          target_step.active = true
          target_step.note = note_name
          target_step.velocity = event.velocity
        end
      end
    end

    # Initialize after loading from MIDI file
    @current_position = 0
  end

  def toggle_step(track_index, step_index)
    track = @tracks[track_index][:steps]
    step = track[step_index]

    step.active = !step.active

    # Set default note if needed for active synth track steps
    if step.active && @tracks[track_index][:midi_note].nil? && step.note.nil?
      step.note = "C4"
    end
  end

  # Transpose note up by one semitone
  def transpose_note_up(step)
    return unless step && step.active && step.note

    note = Note.new.set_by_name(step.note)

    new_midi_note = note.midi_note + 1
    return if new_midi_note > 127  # Check maximum value

    new_note = Note.new.set_by_midi(new_midi_note)

    step.note = "#{new_note.name}#{new_note.octave}"
  end

  # Transpose note down by one semitone
  def transpose_note_down(step)
    return unless step && step.active && step.note

    note = Note.new.set_by_name(step.note)

    new_midi_note = note.midi_note - 1
    return if new_midi_note < 0  # Check minimum value

    new_note = Note.new.set_by_midi(new_midi_note)

    step.note = "#{new_note.name}#{new_note.octave}"
  end

  # Transpose note up by one octave
  def transpose_octave_up(step)
    return unless step && step.active && step.note

    note = Note.new.set_by_name(step.note)

    new_midi_note = note.midi_note + 12
    return if new_midi_note > 127  # Check maximum value

    new_note = Note.new.set_by_midi(new_midi_note)

    step.note = "#{new_note.name}#{new_note.octave}"
  end

  # Transpose note down by one octave
  def transpose_octave_down(step)
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
    print "           "
    puts (1..@steps_per_track).map { |n| n.to_s.rjust(4) }.join

    # 各トラックのステップを表示
    @tracks.each_with_index do |track_info, track_idx|
      track_name = track_info[:name][0..8]

      if track_idx == @current_track
        print "→ #{track_name.ljust(9)} "
      else
        print "  #{track_name.ljust(9)} "
      end

      # トラックのステップを表示
      steps = track_info[:steps]
      puts steps.map.with_index { |step, step_idx|
        # ドラムトラックとシンセトラックで表示を変える
        is_drum = track_info[:midi_note] != nil

        step_display = if is_drum
                         # ドラムの場合はノート表示ではなく「xx」と表示
                         step.active ? "xx" : "__"
                      else
                        # シンセの場合はノート名を表示
                        note_display = step.note && step.active ? step.note[0..1] : "__"
                        note_display
                      end

        if track_idx == @current_track && step_idx == @current_position
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

    puts "\nCommands:"
    puts "  Space: Play/Stop"
    puts "  Arrow keys: Move cursor"
    puts "  Enter: Toggle step"
    puts "  s: Save as MIDI file (format: yyyy-mm-dd-hh-mm-ss.mid)"
    puts "  Ctrl+C: Exit"
  end

  def play_sequence
    return unless @groovebox

    if @playing
      @playing = false

      # 停止時にすべてのアクティブなノートをオフにする
      all_notes_off
      return
    end

    @playing = true
    puts "BPM: #{@bpm}"

    Thread.new do
      step_interval = 60.0 / @bpm / 4
      play_position = 0

      while @playing
        # 各トラックの現在位置のステップをチェック
        @tracks.each do |track_info|
          step = track_info[:steps][play_position]

          if step.active
            instrument_index = track_info[:instrument_index]

            if track_info[:midi_note].nil?
              begin
                # ノート文字列からMIDIノート番号に変換
                note_obj = Note.new.set_by_name(step.note)
                velocity = step.velocity || 100

                @groovebox.change_sequencer_channel(instrument_index)

                # Grooveboxに直接note_onを呼び出す
                @groovebox.sequencer_note_on(note_obj.midi_note, velocity)
              rescue => e
                puts "error synth: #{e.message}"
              end
            else
              # DrumRack
              begin
                midi_note = track_info[:midi_note]
                velocity = step.velocity || 100

                # チャンネルを変更
                @groovebox.change_sequencer_channel(instrument_index)

                # Grooveboxに特定のチャンネルを設定してからnote_onを呼び出す
                @groovebox.sequencer_note_on(midi_note, velocity)
              rescue => e
                puts "error drum: #{e.message}"
              end
            end
          end
        end

        # 少し待ってノートをオフにする
        sleep step_interval * 0.8

        # ノートをオフにする
        @tracks.each do |track_info|
          step = track_info[:steps][play_position]
          if step.active
            instrument_index = track_info[:instrument_index]

            if track_info[:midi_note].nil?
              # Synthesizer
              # TODO: track_infoからは分かりづらいのでclassで判断できるようにする
              begin
                note_obj = Note.new.set_by_name(step.note)
                @groovebox.change_sequencer_channel(instrument_index)
                @groovebox.sequencer_note_off(note_obj.midi_note)
              rescue => e
                puts "error synth: #{e.message}"
              end
            else
              # DrumRack
              begin
                midi_note = track_info[:midi_note]
                @groovebox.change_sequencer_channel(instrument_index)
                @groovebox.sequencer_note_off(midi_note)
              rescue => e
                puts "error drum: #{e.message}"
              end
            end
          end
        end

        # 残りのステップ時間を待つ
        sleep step_interval * 0.2

        # 次のステップへ
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

    # シンセトラックとドラムトラックを分けずに処理
    @tracks.each_with_index do |track_info, track_idx|
      # アクティブなステップがなければ、このトラックをスキップ
      active_steps = track_info[:steps].select(&:active)
      next if active_steps.empty?

      # トラック情報の出力
      track_type = track_info[:midi_note].nil? ? "Synth" : "Drum"
      puts "Track #{track_idx}: #{track_info[:name]} (#{track_type})"

      # MIDIトラック作成
      midi_track = MIDI::Track.new(seq)
      seq.tracks << midi_track
      midi_track.name = track_info[:name]

      # チャンネル設定
      channel = track_info[:midi_note].nil? ? 0 : 9  # シンセなら0、ドラムなら9(チャンネル10)

      # プログラムチェンジ設定
      prog_num = track_info[:instrument_index] % 128
      prog_chg = MIDI::ProgramChange.new(channel, prog_num)
      midi_track.events << prog_chg

      # ステップデータの追加
      ticks_per_step = seq.ppqn / 4.0  # 16分音符あたりのティック数

      last_time = 0  # 前回のタイムスタンプを記録

      # アクティブなステップだけを処理するためにソート
      active_step_indices = []
      track_info[:steps].each_with_index do |step, idx|
        active_step_indices << idx if step.active
      end

      # ステップインデックスでソートして処理
      active_step_indices.sort.each do |step_idx|
        step = track_info[:steps][step_idx]

        # ノートが有効か確認
        next unless step.note

        # ノートの開始位置（ティック単位）
        start_time = (step_idx * ticks_per_step).to_i

        # デルタタイム（前回のイベントからの経過時間）
        delta_time = start_time - last_time
        last_time = start_time

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
          # DrumRackの場合、midi_noteを使用
          midi_note = track_info[:midi_note].to_i
          puts "  Step #{step_idx + 1}: Drum pad #{midi_note}"
        end

        # ベロシティ
        velocity = step.velocity || 100

        # ノートオンイベント
        note_on = MIDI::NoteOn.new(channel, midi_note, velocity)
        note_on.time_from_start = start_time
        midi_track.events << note_on

        # ノートオフイベント
        note_off = MIDI::NoteOff.new(channel, midi_note, 0)
        note_off.time_from_start = start_time + duration
        midi_track.events << note_off
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

  def run
    return puts "Groovebox is not connected" unless @groovebox

    # Initialize if tracks are empty
    initialize_tracks if @tracks.empty?

    loop do
      display
      key = STDIN.getch

      # 現在のステップを取得 (編集モードがないので常に必要)
      current_step = @tracks[@current_track][:steps][@current_position] if @current_track < @tracks.size

      case key
      when "\e" # エスケープキーまたは特殊キー
        # エスケープキーは何もしない (以前は編集モード終了)

        # 矢印キーの場合
        next_key = STDIN.getch
        if next_key == "["
          case STDIN.getch
          when "D" # 左矢印
            @current_position -= 1 if @current_position > 0
          when "C" # 右矢印
            @current_position += 1 if @current_position < @steps_per_track - 1
          when "A" # 上矢印
            @current_track -= 1 if @current_track > 0
          when "B" # 下矢印
            @current_track += 1 if @current_track < @tracks.size - 1
          end
        end
      when "\r" # Enter
        toggle_step(@current_track, @current_position)
      when " " # スペース
        play_sequence
      when "s", "S" # MIDI保存
        save_to_midi_file
      when "\u0003" # Ctrl+C
        @playing = false # Stop if playing
        all_notes_off    # Turn off all notes
        puts "exiting..."
        break
      end
    end
  end
end
