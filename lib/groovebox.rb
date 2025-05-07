class Groovebox
  attr_reader :instruments, :instrument_polyphony
  def initialize
    @instruments = []
    @instrument_polyphony = {}
    @current_channel = 0
    @sequencer_channel = 0
    @sidechain_connections = {}
  end

  def add_instrument(instrument, polyphony = 1)
    instrument_index = @instruments.length
    @instruments.push instrument
    @instrument_polyphony[instrument_index] = [1, [polyphony.to_i, 4].min].max
    instrument_index
  end

  def polyphony(instrument_index)
    @instrument_polyphony[instrument_index] || 1
  end

  def change_channel(channel)
    @current_channel = channel
  end

  def change_sequencer_channel(channel)
    @sequencer_channel = channel
  end

  def current_instrument
    @instruments[@current_channel]
  end

  def sequencer_instrument
    @instruments[@sequencer_channel]
  end

  def current_instrument_index
    @current_channel
  end

  def get_instrument(index)
    @instruments[index]
  end

  def note_on(midi_note, velocity)
    current_instrument.note_on(midi_note, velocity)
  end

  def note_off(midi_note)
    current_instrument.note_off(midi_note)
  end

  def sequencer_note_on(midi_note, velocity)
    sequencer_instrument.note_on(midi_note, velocity)
  end

  def sequencer_note_off(midi_note)
    sequencer_instrument.note_off(midi_note)
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
