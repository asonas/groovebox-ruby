class Sidechain
  attr_accessor :threshold, :ratio, :attack, :release

  def initialize(threshold: 0.5, ratio: 4.0, attack: 0.001, release: 0.2)
    @threshold = threshold  # トリガーがこの値を超えたら処理開始
    @ratio = ratio          # 圧縮比
    @attack = attack        # 圧縮が始まるまでの時間（秒）
    @release = release      # 圧縮が解除されるまでの時間（秒）
    @envelope = 1.0         # 現在の圧縮エンベロープ値
    @sample_rate = 44100    # デフォルトのサンプルレート
  end

  # トリガー信号とターゲット信号を受け取り、サイドチェイン処理を適用
  def process(trigger_samples, target_samples, sample_rate = 44100)
    @sample_rate = sample_rate
    buffer_size = [trigger_samples.length, target_samples.length].min

    processed_samples = target_samples.dup

    buffer_size.times do |i|
      # トリガー信号の強さを検出
      trigger_level = trigger_samples[i].abs

      # しきい値を超えたら圧縮を開始
      if trigger_level > @threshold
        # アタック時間に基づいて圧縮を適用
        @envelope -= @attack * 10  # アタック速度調整
        @envelope = 0.0 if @envelope < 0.0
      else
        # リリース時間に基づいて圧縮を解除
        @envelope += @release / (@sample_rate * 0.1)  # リリース速度調整
        @envelope = 1.0 if @envelope > 1.0
      end

      # ターゲット信号にエンベロープを適用
      processed_samples[i] *= @envelope
    end

    processed_samples
  end
end
