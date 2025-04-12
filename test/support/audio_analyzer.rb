# frozen_string_literal: true

require 'wavefile'
require 'minitest/autorun'

module TestSupport
  # 音声ファイルの周波数分析を行うクラス
  class AudioAnalyzer
    # デバッグモード（ログ出力の有無）
    DEBUG = false

    # MIDIノート番号から周波数を計算する定数
    MIDI_NOTE_TO_FREQ = {}
    (0..127).each do |midi_note|
      MIDI_NOTE_TO_FREQ[midi_note] = 440.0 * (2.0 ** ((midi_note - 69) / 12.0))
    end

    def initialize(wav_file_path)
      @wav_file_path = wav_file_path
      @sample_rate = nil
      @samples = nil
      load_samples
    end

    # WAVファイルからサンプルを読み込む
    def load_samples
      reader = WaveFile::Reader.new(@wav_file_path)
      @sample_rate = reader.format.sample_rate

      # サンプルを配列に読み込む
      buffer_size = 4096
      buffer = reader.read(buffer_size)
      @samples = []

      # チャンネルが複数ある場合は最初のチャンネルだけを使用
      until buffer.samples.empty?
        if buffer.samples[0].is_a?(Array)
          # ステレオの場合は左チャンネルを使用
          @samples.concat(buffer.samples.map { |s| s[0] })
        else
          @samples.concat(buffer.samples)
        end

        break if @samples.length >= buffer_size * 4 # 解析のための十分なサンプルを取得
        buffer = reader.read(buffer_size)
      end

      reader.close
    end

    # 単純なDFT（離散フーリエ変換）を実装
    def analyze_frequencies(start_freq = 20, end_freq = 1000, resolution = 1.0)
      results = {}
      return results if @samples.nil? || @samples.empty?

      # 解析する周波数範囲を設定
      frequencies = []
      freq = start_freq
      while freq <= end_freq
        frequencies << freq
        freq += resolution
      end

      # 各周波数に対してDFTを実行
      frequencies.each do |frequency|
        # 周波数に対応する角速度（ラジアン/サンプル）
        omega = 2.0 * Math::PI * frequency / @sample_rate

        # 実部と虚部に分けて計算
        real_sum = 0.0
        imag_sum = 0.0

        @samples.each_with_index do |sample, n|
          real_sum += sample * Math.cos(omega * n)
          imag_sum -= sample * Math.sin(omega * n)
        end

        # 振幅を計算
        amplitude = Math.sqrt(real_sum * real_sum + imag_sum * imag_sum) / @samples.length
        results[frequency] = amplitude
      end

      results
    end

    # 主要な周波数のピークを検出
    def detect_frequency_peaks(threshold = 0.01, max_peaks = 5)
      frequencies = analyze_frequencies()
      return [] if frequencies.empty?

      # 振幅でソート
      sorted_freqs = frequencies.sort_by { |_, amplitude| -amplitude }

      # しきい値以上の振幅を持つ周波数を抽出
      peaks = sorted_freqs.select { |_, amplitude| amplitude >= threshold }.take(max_peaks)

      # 周波数のみを返す
      peaks.map { |frequency, _| frequency }
    end

    # 特定のMIDIノートに対応する周波数が含まれているかをチェック
    def has_frequency_for_midi_note?(midi_note, tolerance_percent = 5.0)
      return false if @samples.nil? || @samples.empty?

      expected_freq = MIDI_NOTE_TO_FREQ[midi_note]
      tolerance = expected_freq * (tolerance_percent / 100.0)

      # 指定された範囲の周波数を集中的に分析
      min_freq = expected_freq - tolerance
      max_freq = expected_freq + tolerance

      # 高分解能でこの範囲を分析
      resolution = tolerance / 10.0
      frequencies = analyze_frequencies(min_freq, max_freq, resolution)

      # 最大振幅の周波数を見つける
      max_amplitude = 0.0
      max_freq = nil

      frequencies.each do |freq, amplitude|
        if amplitude > max_amplitude
          max_amplitude = amplitude
          max_freq = freq
        end
      end

      return false if max_freq.nil?

      # 期待される周波数との差を計算
      difference = (max_freq - expected_freq).abs

      # 周波数の差が許容範囲内であるかをチェック
      difference <= tolerance
    end

    # 複数のMIDIノートが音声に含まれているかをチェック
    def check_midi_notes(midi_notes, tolerance_percent = 5.0)
      results = {}

      midi_notes.each do |note|
        results[note] = has_frequency_for_midi_note?(note, tolerance_percent)
      end

      results
    end
  end
end
