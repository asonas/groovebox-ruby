class Note
  BASE_FREQUENCY = 440.0
  NOTE_NAMES = %w[C C# D D# E F F# G G# A A# B].freeze

  attr_accessor :phase, :note_on_sample_index, :note_off_sample_index, :midi_note

  def initialize
    @semitone = 0
    @midi_note = 69 # A4
    @phase = 0.0
    @note_on_sample_index = nil
    @note_off_sample_index = nil
  end

  def frequency
    BASE_FREQUENCY * (2 ** (@semitone / 12.0))
  end

  def set_by_name(name)
    note_index = NOTE_NAMES.index(name[0..-2]) # 音階部分
    octave = name[-1].to_i
    @semitone = (octave - 4) * 12 + note_index - 9
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
