# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require_relative '../../lib/synthesizer'
require_relative '../support/audio_analyzer'
require_relative '../support/test_vca'
require_relative '../../lib/presets/acid_bass'
require_relative '../../lib/presets/moog_lead'

# シンセサイザーの周波数テスト
class FrequencyTest < Minitest::Test
  SAMPLE_RATE = 44100
  BUFFER_SIZE = 128
  AMPLITUDE = 1000
  TEST_DURATION = 0.5 # 秒

  def setup
    # テスト用の出力ディレクトリを作成
    @output_dir = 'tmp/test_audio'
    FileUtils.mkdir_p(@output_dir) unless Dir.exist?(@output_dir)
  end

  def test_acid_bass_single_note_frequency
    # MIDIノート設定
    midi_note = 60 # C4 (ド)

    # Acid Bassの設定
    synth = Presets::AcidBass.new(SAMPLE_RATE, AMPLITUDE)

    # 音声ファイルのパス
    output_file = File.join(@output_dir, 'acid_bass_frequency_test.wav')

    # 音声生成
    test_vca = TestVCA.new(synth, SAMPLE_RATE, BUFFER_SIZE, output_file)
    synth.note_on(midi_note, 100)
    test_vca.generate_samples(BUFFER_SIZE, TEST_DURATION)
    synth.note_off(midi_note)
    test_vca.generate_samples(BUFFER_SIZE, 0.2) # リリース部分
    test_vca.save_to_file(:wav)

    # 周波数分析
    analyzer = TestSupport::AudioAnalyzer.new(output_file)

    # 期待されるMIDIノートの周波数が存在するか確認
    has_expected_freq = analyzer.has_frequency_for_midi_note?(midi_note)

    assert has_expected_freq, "生成された音声にMIDIノート#{midi_note}の周波数が含まれていません"
  end

  def test_acid_bass_sequence
    # MIDIノートシーケンス
    midi_notes = [36, 48, 60, 72] # C2, C3, C4, C5（オクターブ上昇）

    # Acid Bassの設定
    synth = Presets::AcidBass.new(SAMPLE_RATE, AMPLITUDE)

    # 音声ファイルのパス
    output_file = File.join(@output_dir, 'acid_bass_sequence_test.wav')

    # 音声生成
    test_vca = TestVCA.new(synth, SAMPLE_RATE, BUFFER_SIZE, output_file)

    # シーケンスを生成
    midi_notes.each do |note|
      synth.note_on(note, 100)
      test_vca.generate_samples(BUFFER_SIZE, 0.3)
      synth.note_off(note)
      test_vca.generate_samples(BUFFER_SIZE, 0.1) # ノート間のギャップ
    end

    test_vca.save_to_file(:wav)

    # 音声ファイルを分割して各部分を分析
    # 簡略化のため、各ノートが0.4秒の長さを持つと仮定
    total_samples = (SAMPLE_RATE * 0.4 * midi_notes.length).to_i
    samples_per_note = (SAMPLE_RATE * 0.4).to_i

    # 各ノートの時間位置を計算
    note_positions = midi_notes.each_with_index.map do |note, index|
      [note, index * 0.4] # [MIDIノート, 開始時間(秒)]
    end

    # 簡易版：音声全体で全てのノートの周波数が含まれているか確認
    analyzer = TestSupport::AudioAnalyzer.new(output_file)

    # 各ノートに対して個別にテスト
    results = analyzer.check_midi_notes(midi_notes)

    # すべてのノートに対応する周波数が少なくとも1つは検出されるべき
    midi_notes.each do |note|
      assert results[note], "MIDIノート#{note}の周波数が検出されませんでした"
    end
  end

  def test_moog_lead_frequency
    # MIDIノート設定
    midi_note = 60 # C4 (ド)

    # Moog Leadの設定
    synth = Presets::MoogLead.new(SAMPLE_RATE, AMPLITUDE)

    # 音声ファイルのパス
    output_file = File.join(@output_dir, 'moog_lead_frequency_test.wav')

    # 音声生成
    test_vca = TestVCA.new(synth, SAMPLE_RATE, BUFFER_SIZE, output_file)
    synth.note_on(midi_note, 100)
    test_vca.generate_samples(BUFFER_SIZE, TEST_DURATION)
    synth.note_off(midi_note)
    test_vca.generate_samples(BUFFER_SIZE, 0.2) # リリース部分
    test_vca.save_to_file(:wav)

    # 周波数分析
    analyzer = TestSupport::AudioAnalyzer.new(output_file)

    # 期待されるMIDIノートの周波数が存在するか確認
    has_expected_freq = analyzer.has_frequency_for_midi_note?(midi_note)

    assert has_expected_freq, "生成された音声にMIDIノート#{midi_note}の周波数が含まれていません"
  end

  def test_c_major_scale
    # Cメジャースケール（C4からC5まで）
    scale_notes = [60, 62, 64, 65, 67, 69, 71, 72] # C, D, E, F, G, A, B, C

    # Acid Bassで音階を生成
    synth = Presets::AcidBass.new(SAMPLE_RATE, AMPLITUDE)

    # 音声ファイルのパス
    output_file = File.join(@output_dir, 'c_major_scale_frequency_test.wav')

    # 音声生成
    test_vca = TestVCA.new(synth, SAMPLE_RATE, BUFFER_SIZE, output_file)

    # スケールを生成
    scale_notes.each do |note|
      synth.note_on(note, 100)
      test_vca.generate_samples(BUFFER_SIZE, 0.3)
      synth.note_off(note)
      test_vca.generate_samples(BUFFER_SIZE, 0.1) # ノート間のギャップ
    end

    test_vca.save_to_file(:wav)

    # 音声分析
    analyzer = TestSupport::AudioAnalyzer.new(output_file)

    # 各ノートに対して個別にテスト
    results = analyzer.check_midi_notes(scale_notes)

    # すべてのノートが検出されるべき
    scale_notes.each do |note|
      assert results[note], "Cメジャースケールの音階 MIDIノート#{note}が検出されませんでした"
    end
  end
end
