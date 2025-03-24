class VCF
  attr_accessor :low_pass_cutoff, :high_pass_cutoff, :resonance

  def initialize(sample_rate)
    @sample_rate = sample_rate
    @low_pass_cutoff = 1000.0
    @high_pass_cutoff = 100.0
    @resonance = 0.0
    reset_filters
  end

  def apply(input)
    low_pass(high_pass(input))
  end

  def low_pass_cutoff=(new_frequency)
    @low_pass_cutoff = [[new_frequency, 20.0].max, @sample_rate / 2.0].min
    update_low_pass_alpha
  end

  def high_pass_cutoff=(new_frequency)
    @high_pass_cutoff = [[new_frequency, 20.0].max, @sample_rate / 2.0].min
    update_high_pass_alpha
  end

  def resonance=(new_resonance)
    @resonance = [[new_resonance, 0.0].max, 0.99].min  # 発振防止のため上限を0.99とする
    # resonanceを更新したらフィルターを更新
    update_low_pass_filters
  end

  # サンプル配列に対してフィルタ処理を行う
  # @param samples [Array<Float>] 処理する波形サンプルの配列
  # @param filter_type [Symbol] 適用するフィルターの種類 (:low_pass, :high_pass, :band_pass, :all)
  # @return [Array<Float>] フィルター適用後のサンプル配列
  def process(samples, filter_type = :all)
    case filter_type
    when :low_pass
      # 低域通過フィルターのみ適用
      processed_samples = samples.map { |sample| low_pass(sample) }
    when :high_pass
      # 高域通過フィルターのみ適用
      processed_samples = samples.map { |sample| high_pass(sample) }
    when :band_pass
      # バンドパスフィルター（低域と高域の両方を適用）
      processed_samples = samples.map { |sample| low_pass(high_pass(sample)) }
    when :all
      # すべてのフィルターを適用（既存のapplyメソッドと同等）
      processed_samples = samples.map { |sample| apply(sample) }
    else
      # 不明なフィルタータイプの場合は元のサンプルを返す
      return samples
    end

    # フィルター適用後のサンプルを返す
    processed_samples
  end

  private

  def reset_filters
    @low_pass_prev_output = 0.0
    @low_pass_prev_input = 0.0
    @high_pass_prev_input = 0.0
    @high_pass_prev_output = 0.0
    update_low_pass_alpha
    update_high_pass_alpha
    update_low_pass_filters
  end

  def update_low_pass_alpha
    rc = 1.0 / (2.0 * Math::PI * @low_pass_cutoff)
    @low_pass_alpha = rc / (rc + 1.0 / @sample_rate)
  end

  def update_high_pass_alpha
    rc = 1.0 / (2.0 * Math::PI * @high_pass_cutoff)
    @high_pass_alpha = rc / (rc + 1.0 / @sample_rate)
  end

  def update_low_pass_filters
    @feedback = @resonance * 3.8  # 3.8はフィードバック係数。マジックナンバー
  end

  def low_pass(input)
    return @low_pass_prev_output if input.nil?

    input = input.clamp(-10.0, 10.0)

    # レゾナンスが設定されている場合はフィードバックする
    if @resonance > 0.01
      feedback_value = @low_pass_prev_output * @feedback

      # NaNチェック - フィードバック値が無効な場合はフィードバックを適用しない
      feedback_value = 0.0 if feedback_value.nan? || feedback_value.infinite?

      # 入力からフィードバックを減算
      filtered_input = input - feedback_value

      # フィルター係数を適用
      output = @low_pass_alpha * filtered_input + (1 - @low_pass_alpha) * @low_pass_prev_output

      @low_pass_prev_input = input
      @low_pass_prev_output = output

      # クリッピング防止
      output.clamp(-3.0, 3.0)
    else
      output = @low_pass_alpha * input + (1 - @low_pass_alpha) * @low_pass_prev_output
      @low_pass_prev_input = input
      @low_pass_prev_output = output
      output
    end
  end

  def high_pass(input)
    return @high_pass_prev_output if input.nil?

    input = input.clamp(-10.0, 10.0)

    output = (1 - @high_pass_alpha) * (@high_pass_prev_output + input - @high_pass_prev_input)
    @high_pass_prev_input = input
    @high_pass_prev_output = output
    output
  end
end
