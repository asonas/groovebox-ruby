class Envelope
  attr_accessor :attack, :decay, :sustain, :release

  def initialize(attack: 0.01, decay: 0.1, sustain: 0.7, release: 0.5)
    @attack = attack
    @decay = decay
    @sustain = sustain
    @release = release
  end

  # サンプル単位で経過秒を計算する
  # sample_index: 現在のサンプル番号
  # sample_rate: サンプリングレート
  def apply_envelope(note, sample_index, sample_rate)
    # Note.on / off 時刻（サンプル番号）がnilなら鳴っていないか無音扱い
    return 0.0 if note.note_on_sample_index.nil?

    current_sample_offset = sample_index - note.note_on_sample_index
    # まだノートオンしていない未来のサンプルを参照してしまったら0
    return 0.0 if current_sample_offset < 0

    current_time = current_sample_offset.to_f / sample_rate

    if note.note_off_sample_index.nil?
      # ノートオン〜
      if current_time < @attack
        # Attack
        current_time / @attack
      elsif current_time < (@attack + @decay)
        # Decay
        1.0 - ((current_time - @attack) / @decay) * (1.0 - @sustain)
      else
        # Sustain
        @sustain
      end
    else
      # Release中
      release_start_offset = note.note_off_sample_index - note.note_on_sample_index
      # Releaseを開始してから何サンプル経ったか
      release_sample_offset = sample_index - note.note_off_sample_index
      return 0.0 if release_sample_offset < 0  # まだノートオフしてない時点なら sustain値を適用

      release_time = release_sample_offset.to_f / sample_rate

      # # リリース開始前の値 = Attack -> Decay -> Sustain の順で計算
      # TODO: 期待した動きになってないのであとで直す
      # if release_start_offset < @attack * sample_rate
      #   # Attack途中でオフになった
      #   release_start_offset.to_f / sample_rate / @attack
      # elsif release_start_offset < (@attack + @decay) * sample_rate
      #   # Decay途中でオフになった
      #   1.0 - ((release_start_offset - @attack * sample_rate) / (@decay * sample_rate)) * (1.0 - @sustain)
      # else
      # end

      # リリース計算
      volume_at_release_start = sustain_level_at_release(note, release_start_offset, sample_rate)
      envelope_val = volume_at_release_start * (1.0 - (release_time / @release))
      envelope_val.negative? ? 0.0 : envelope_val
    end.clamp(0.0, 1.0)
  end

  private

  # リリース開始時点(= note_off_sample_index) でのエンベロープレベルを求める
  def sustain_level_at_release(note, release_start_offset, sample_rate)
    # release_start_offset: ノートオンからノートオフまでのサンプル数
    release_start_time = release_start_offset.to_f / sample_rate

    if release_start_time < @attack
      # Attack途中でオフになった
      release_start_time / @attack
    elsif release_start_time < (@attack + @decay)
      # Decay途中でオフになった
      1.0 - ((release_start_time - @attack) / @decay) * (1.0 - @sustain)
    else
      # Sustain状態でオフ
      @sustain
    end
  end
end
