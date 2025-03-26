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

  # ノート名からMIDIノート番号へのマッピング
  NOTE_TO_MIDI = {}
  DEFAULT_NOTES.each_with_index do |note_name, idx|
    NOTE_TO_MIDI[note_name] = 48 + idx  # C3 = 48から始まる
  end

  def initialize(groovebox = nil, mid_file_path = nil)
    @groovebox = groovebox
    @current_position = 0
    @current_track = 0
    @steps_per_track = 32
    @tracks = []
    @playing = false
    @bpm = 120
    @editing_mode = false
    @edit_note_index = 0

    # Grooveboxからトラック情報を取得
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
        # DrumRackの場合は各パッドを別トラックとして扱う
        instrument.pad_notes.sort.each do |pad_note|
          track = Array.new(@steps_per_track) { Step.new }
          @tracks << { name: "Drum #{pad_note}", instrument_index: idx, midi_note: pad_note, steps: track }
        end
      else
        track = Array.new(@steps_per_track) { Step.new }
        @tracks << { name: track_name, instrument_index: idx, midi_note: nil, steps: track }
      end
    end

    # トラックが空の場合はデフォルトのトラックを作成
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

    # MIDIファイルの各トラックをステップシーケンスのトラックにマッピング
    seq.tracks.each_with_index do |midi_track, track_index|
      note_on_events = midi_track.events.select do |event|
        event.kind_of?(MIDI::NoteOn) && event.velocity > 0
      end

      next if note_on_events.empty?

      # 既存のトラックがあればそれを使用、なければ新規作成
      if track_index < @tracks.size
        track = @tracks[track_index][:steps]
      else
        track = Array.new(@steps_per_track) { Step.new }
        @tracks << { name: "Track #{track_index}", instrument_index: 0, midi_note: nil, steps: track }
      end

      max_time = note_on_events.map(&:time_from_start).max
      ticks_per_step = seq.ppqn / 4.0

      note_on_events.each do |event|
        step_index = (event.time_from_start / ticks_per_step).to_i
        next if step_index >= @steps_per_track

        track[step_index].active = true
        track[step_index].note = "#{event.note}"
        track[step_index].velocity = event.velocity
      end
    end
  end

  def toggle_step(track_index, step_index)
    track = @tracks[track_index][:steps]
    step = track[step_index]

    step.active = !step.active

    # TODO: edding_modeは削除する
    if step.active
      @editing_mode = true
      if @tracks[track_index][:midi_note]
        @editing_mode = false
      end
    else
      @editing_mode = false
    end
  end

  # ノートを半音上げる
  def transpose_note_up(step)
    return unless step && step.active && step.note

    note = Note.new.set_by_name(step.note)

    new_midi_note = note.midi_note + 1
    return if new_midi_note > 127  # 最大値チェック

    new_note = Note.new.set_by_midi(new_midi_note)

    step.note = "#{new_note.name}#{new_note.octave}"

    preview_note(step.note)
  end

  # ノートを半音下げる
  def transpose_note_down(step)
    return unless step && step.active && step.note

    note = Note.new.set_by_name(step.note)

    new_midi_note = note.midi_note - 1
    return if new_midi_note < 0  # 最小値チェック

    new_note = Note.new.set_by_midi(new_midi_note)

    step.note = "#{new_note.name}#{new_note.octave}"

    preview_note(step.note)
  end

  # ノートを1オクターブ上げる
  def transpose_octave_up(step)
    return unless step && step.active && step.note

    note = Note.new.set_by_name(step.note)

    new_midi_note = note.midi_note + 12
    return if new_midi_note > 127  # 最大値チェック

    new_note = Note.new.set_by_midi(new_midi_note)

    step.note = "#{new_note.name}#{new_note.octave}"

    preview_note(step.note)
  end

  # ノートを1オクターブ下げる
  def transpose_octave_down(step)
    return unless step && step.active && step.note

    note = Note.new.set_by_name(step.note)

    new_midi_note = note.midi_note - 12
    return if new_midi_note < 0  # 最小値チェック

    new_note = Note.new.set_by_midi(new_midi_note)

    step.note = "#{new_note.name}#{new_note.octave}"

    preview_note(step.note)
  end

  # 現在のノートをプレビュー再生する
  def preview_note(note_name)
    return unless @groovebox && note_name

    return if @current_track >= @tracks.size

    track = @tracks[@current_track]
    instrument_index = track[:instrument_index]

    # Grooveboxのチャンネルを選択
    @groovebox.change_sequencer_channel(instrument_index)

    begin
      note = Note.new.set_by_name(note_name)
      @groovebox.sequencer_note_on(note.midi_note, 100)

      Thread.new do
        sleep 0.1
        @groovebox.sequencer_note_off(note.midi_note)
      end
    rescue => e
      puts "error preview_note: #{e.message}"
    end
  end

  def display
    system('clear')
    puts "Groovebox Sequencer" + (@playing ? " (再生中)" : "") + (@editing_mode ? " [ノート編集モード]" : "")
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
        if track_idx == @current_track && step_idx == @current_position
          if @editing_mode && step.active
            "[#{step.note[0..1]}*"  # ノート編集中は*で表示
          elsif step.active
            "[#{step.note[0..1]}]"
          else
            "[__]"
          end
        else
          step.active ? " #{step.note[0..1]} " : " __ "
        end
      }.join
    end
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

  def run
    return puts "Groovebox is not connected" unless @groovebox

    # トラックが空の場合は初期化
    initialize_tracks if @tracks.empty?

    loop do
      display
      key = STDIN.getch

      # 現在のステップを取得
      current_step = @tracks[@current_track][:steps][@current_position] if @current_track < @tracks.size

      case key
      when 'h', 'H' # 半音下げる
        if current_step && current_step.active && !@tracks[@current_track][:midi_note]
          transpose_note_down(current_step)
        end
      when 'l', 'L' # 半音上げる
        if current_step && current_step.active && !@tracks[@current_track][:midi_note]
          transpose_note_up(current_step)
        end
      when 'y', 'Y' # 1オクターブ下げる
        if current_step && current_step.active && !@tracks[@current_track][:midi_note]
          transpose_octave_down(current_step)
        end
      when 'o', 'O' # 1オクターブ上げる
        if current_step && current_step.active && !@tracks[@current_track][:midi_note]
          transpose_octave_up(current_step)
        end
      when "\e" # エスケープキーまたは特殊キー
        # エスケープキーの場合、編集モードを終了
        if @editing_mode
          @editing_mode = false
          next
        end

        # 矢印キーの場合
        next_key = STDIN.getch
        if next_key == "["
          case STDIN.getch
          when "D" # 左矢印
            if @editing_mode
              @edit_note_index = (@edit_note_index - 1) % DEFAULT_NOTES.size
            else
              @current_position -= 1 if @current_position > 0
            end
          when "C" # 右矢印
            if @editing_mode
              @edit_note_index = (@edit_note_index + 1) % DEFAULT_NOTES.size
            else
              @current_position += 1 if @current_position < @steps_per_track - 1
            end
          when "A" # 上矢印
            unless @editing_mode
              @current_track -= 1 if @current_track > 0
            end
          when "B" # 下矢印
            unless @editing_mode
              @current_track += 1 if @current_track < @tracks.size - 1
            end
          end
        end
      when "\r" # Enter
        if @editing_mode
          # ノート編集モードでEnterを押した場合、編集を終了
          @editing_mode = false
        else
          # 通常モードでEnterを押した場合、ステップを切り替え
          toggle_step(@current_track, @current_position)
        end
      when " " # スペース
        unless @editing_mode
          play_sequence
        end
      when "\u0003" # Ctrl+C
        @playing = false # 再生中なら停止
        all_notes_off    # すべてのノートをオフにする
        puts "exiting..."
        break
      end
    end
  end
end
