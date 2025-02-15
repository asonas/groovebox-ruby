class Envelope
  attr_accessor :attack, :decay, :sustain, :release

  def initialize(attack: 0.01, decay: 0.1, sustain: 0.7, release: 0.5)
    @attack = attack
    @decay = decay
    @sustain = sustain
    @release = release
  end

  def apply_envelope(note_data, sample_index)
    note_on_time = note_data[:note_on_time]
    note_off_time = note_data[:note_off_time]
    current_time = note_on_time.nil? ? 0.0 : (Time.now - note_on_time) # 発音からの経過秒

    # Attack, Decay, Sustain
    env_value =
      if note_off_time.nil?
        # ノートオン 〜 Attack
        if current_time < @attack
          current_time / @attack
        # Attack 〜 Decay
        elsif current_time < (@attack + @decay)
          1.0 - ( (current_time - @attack) / @decay ) * (1.0 - @sustain)
        else
          # Sustain
          @sustain
        end
      else
        # リリースフェーズ: note_off_timeからの経過時間に応じて減衰する
        release_elapsed = Time.now - note_off_time
        release_elapsed < @release ? @sustain * (1.0 - release_elapsed / @release) : 0.0
      end

    env_value.clamp(0.0, 1.0)
  end
end
