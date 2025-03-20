require 'minitest/autorun'
require 'fileutils'
require 'wavefile'
require_relative '../support/test_vca'
require_relative '../../lib/synthesizer'
require_relative '../../lib/presets/moog_lead'

FileUtils.mkdir_p('tmp/test_audio')

class MoogLeadTest < Minitest::Test
  SAMPLE_RATE = 44100
  BUFFER_SIZE = 128
  AMPLITUDE = 1000

  def setup
    @moog_lead = Presets::MoogLead.new(SAMPLE_RATE, AMPLITUDE)
    @test_vca = TestVCA.new(@moog_lead, SAMPLE_RATE, BUFFER_SIZE, 'tmp/test_audio/moog_lead_test.wav')
  end

  def test_single_note_generation
    # C4(ド)の音を鳴らす（MIDIノート60）
    midi_note = 60
    velocity = 100

    # ノートをオンにする
    @moog_lead.note_on(midi_note, velocity)

    # 1秒間の音声を生成
    @test_vca.generate_samples(BUFFER_SIZE, 1.0)

    # ノートをオフにする
    @moog_lead.note_off(midi_note)

    # リリース部分も含めてさらに0.5秒生成
    @test_vca.generate_samples(BUFFER_SIZE, 0.5)

    output_file = @test_vca.save_to_file

    # ファイルが存在することを確認
    assert File.exist?(output_file), "Audio file was not generated"

    # バッファの内容を検証
    buffer = @test_vca.get_buffer

    # バッファが空でないことを確認
    refute_empty buffer, "Generated audio buffer is empty"

    # サンプル値が適切な範囲内にあることを確認（クリッピングがないか）
    max_amplitude = buffer.map(&:abs).max
    assert max_amplitude > 0, "No audio signal was generated"
    assert max_amplitude <= 32768, "Audio signal is clipping"

    # 一部のサンプルでゼロでない値があることを確認（無音でないか）
    non_zero_samples = buffer.reject { |sample| sample == 0 }
    assert non_zero_samples.length > 0, "Generated audio is silent"

    puts "Test successful: Audio file generated: #{output_file}"
  end

  def test_c_major_scale
    # テスト用に別のVCAを用意 (クリアなバッファで開始)
    scale_output_file = 'tmp/test_audio/c_major_scale.wav'
    scale_vca = TestVCA.new(@moog_lead, SAMPLE_RATE, BUFFER_SIZE, scale_output_file)

    # Cメジャースケールの各音を順番に鳴らして保存
    scale_notes = [60, 62, 64, 65, 67, 69, 71, 72] # C4, D4, E4, F4, G4, A4, B4, C5

    # 各ノートを0.5秒間鳴らす
    scale_notes.each do |midi_note|
      @moog_lead.note_on(midi_note, 100)
      # 音を鳴らす (0.3秒)
      scale_vca.generate_samples(BUFFER_SIZE, 0.3)
      # ノートオフ
      @moog_lead.note_off(midi_note)
      # リリース (0.2秒)
      scale_vca.generate_samples(BUFFER_SIZE, 0.2)
    end

    # スケール全体をファイルに保存
    output_file = scale_vca.save_to_file(:wav)

    assert File.exist?(output_file), "Scale audio file was not generated"

    # バッファの長さが期待通りであることを確認
    # 1音あたり0.5秒、8音で約4秒 = 44100 * 4 = 176400サンプル程度を期待
    expected_min_length = (SAMPLE_RATE * 0.5 * scale_notes.length * 0.9).to_i  # 少し余裕を持たせる
    assert scale_vca.get_buffer.length >= expected_min_length,
           "Buffer length is shorter than expected (#{scale_vca.get_buffer.length} < #{expected_min_length})"

    puts "Test successful: C major scale audio file generated: #{output_file}"
  end

  # 異なるパラメータでの音色テスト
  def test_different_parameters
    params_output_file = 'tmp/test_audio/moog_lead_params_test.wav'
    params_vca = TestVCA.new(@moog_lead, SAMPLE_RATE, BUFFER_SIZE, params_output_file)

    @moog_lead.envelope.attack = 0.2
    @moog_lead.envelope.decay = 0.3
    @moog_lead.envelope.sustain = 0.5
    @moog_lead.envelope.release = 0.5

    @moog_lead.filter_cutoff = 2000.0
    @moog_lead.filter_resonance = 0.6

    midi_note = 60  # C4
    @moog_lead.note_on(midi_note, 100)
    params_vca.generate_samples(BUFFER_SIZE, 1.0)
    @moog_lead.note_off(midi_note)
    params_vca.generate_samples(BUFFER_SIZE, 0.7)

    output_file = params_vca.save_to_file(:wav)

    assert File.exist?(output_file), "Audio file with different parameters was not generated"

    puts "Test successful: Audio file with different parameters generated: #{output_file}"
  end
end

if __FILE__ == $PROGRAM_NAME
  Minitest.run
end
