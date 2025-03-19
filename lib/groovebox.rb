class Groovebox
  attr_reader :instruments
  def initialize
    @instruments = []
    @current_channel = 0
    @sidechain_connections = {}  # サイドチェイン接続を保存
  end

  def add_instrument(instrument)
    @instruments.push instrument
  end

  def change_channel(channel)
    @current_channel = channel
  end

  def current_instrument
    @instruments[@current_channel]
  end

  def note_on(midi_note, velocity)
    current_instrument.note_on(midi_note, velocity)
  end

  def note_off(midi_note)
    current_instrument.note_off(midi_note)
  end

  # サイドチェイン接続を設定
  # @param trigger_index [Integer] トリガーとなるインストゥルメントのインデックス
  # @param target_index [Integer] 効果を受けるインストゥルメントのインデックス
  # @param options [Hash] サイドチェインのパラメータ
  def setup_sidechain(trigger_index, target_index, options = {})
    return if trigger_index >= @instruments.length || target_index >= @instruments.length

    sidechain = Sidechain.new(
      threshold: options[:threshold] || 0.3,
      ratio: options[:ratio] || 4.0,
      attack: options[:attack] || 0.001,
      release: options[:release] || 0.2
    )

    @sidechain_connections[target_index] = {
      trigger: trigger_index,
      processor: sidechain,
    }
  end

  def generate(frame_count)
    # 各インストゥルメントの生の出力を保存
    raw_outputs = []
    @instruments.each do |instrument|
      raw_outputs << instrument.generate(frame_count)
    end

    processed_outputs = raw_outputs.dup
    @sidechain_connections.each do |target_idx, connection|
      trigger_idx = connection[:trigger]
      sidechain = connection[:processor]

      processed_outputs[target_idx] = sidechain.process(
        raw_outputs[trigger_idx],
        raw_outputs[target_idx],
        SAMPLE_RATE
      )
    end

    mixed_samples = Array.new(frame_count, 0.0)
    active_instruments = 0

    processed_outputs.each do |samples|
      next if samples.all? { |sample| sample.zero? }

      mixed_samples = mixed_samples.zip(samples).map { |a, b| a + b }
      active_instruments += 1
    end

    if active_instruments > 1
      gain_adjustment = 1.0 / Math.sqrt(active_instruments)
      mixed_samples.map! { |sample| sample * gain_adjustment }
    end

    mixed_samples
  end
end
