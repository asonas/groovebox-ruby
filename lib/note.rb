class Note
  BASE_FREQUENCY = 440.0
  NOTE_NAMES = %w[C C# D D# E F F# G G# A A# B].freeze

  attr_accessor :phase, :note_on_sample_index, :note_off_sample_index, :midi_note, :velocity
  attr_accessor :custom_envelope, :filter_cutoff

  def initialize
    @semitone = 0
    @midi_note = 69 # A4
    @phase = 0.0
    @note_on_sample_index = nil
    @note_off_sample_index = nil
    @velocity = 1.0
    @custom_envelope = nil
    @filter_cutoff = nil
  end

  def frequency
    BASE_FREQUENCY * (2 ** (@semitone / 12.0))
  end

  def set_by_name(name)
    return self if name.nil? || name.empty?

    begin
      note_name = name.gsub(/[0-9]/, '')  # 数字を削除してノート名を取得
      octave = name.gsub(/[^0-9]/, '').to_i  # 数字のみを取得して音高を取得

      note_index = NOTE_NAMES.index(note_name)
      return self if note_index.nil?  # 無効なノート名の場合は変更しない

      @semitone = (octave - 4) * 12 + note_index - 9
      @midi_note = @semitone + 69

      @midi_note = @midi_note.clamp(0, 127)
    rescue => e
      puts "ノート設定エラー: #{e.message} (入力: #{name})"
    end

    self
  end

  # MIDIノート番号で示される音高を、A4(=69番)を基準に
  # 「何半音ずれているか」を計算し、@semitone に格納する。
  # 例えば、MIDIノート60はC4で、これを渡すと
  #  60 - 69 = -9
  # となり、440Hzを基準に -9 半音分だけ低い周波数になる。
  #
  # @param [Integer] midi_note MIDIノート番号(0〜127)
  # @return [Note] self
  def set_by_midi(midi_note)
    @midi_note = midi_note
    @semitone = midi_note - 69
    self
  end

  def name
    NOTE_NAMES[(@semitone + 9) % 12]
  end

  def octave
    4 + ((@semitone + 9) / 12)
  end

  def display
    "#{name}#{octave} (#{frequency.round(2)} Hz)"
  end
end
