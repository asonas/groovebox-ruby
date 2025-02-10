class Note
  BASE_FREQUENCY = 440.0
  NOTE_NAMES = %w[C C# D D# E F F# G G# A A# B].freeze

  def initialize
    @semitone = 0
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
