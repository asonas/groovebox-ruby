require 'wavefile'

class TestVCA
  def initialize(generator, sample_rate, buffer_size, output_path = 'tmp/test_output.wav')
    @generator = generator
    @buffer_size = buffer_size
    @sample_rate = sample_rate
    @output_path = output_path
    @buffer = []

    output_dir = File.dirname(@output_path)
    Dir.mkdir(output_dir) unless Dir.exist?(output_dir)
  end

  def process(frame_count)
    samples = @generator.generate(frame_count)
    @buffer.concat(samples)
    :paContinue
  end

  def generate_samples(frames, note_duration = 1.0)
    total_frames = (note_duration * @sample_rate).to_i
    frames_processed = 0

    while frames_processed < total_frames
      frames_to_process = [frames, total_frames - frames_processed].min
      process(frames_to_process)
      frames_processed += frames_to_process
    end

    @buffer
  end

  # 内部バッファの内容を音声ファイルとして保存
  def save_to_file(format = :wav)
    case format
    when :wav
      save_to_wav
    else
      raise "Unsupported format: #{format}"
    end
  end

  def save_to_wav
    buffer = @buffer.map { |sample| sample / 32768.0 } # 正規化 (-1.0 ~ 1.0 の範囲に)

    WaveFile::Writer.new(@output_path, WaveFile::Format.new(:mono, :float, @sample_rate)) do |writer|
      # バッファを適切なサイズのチャンクに分割して書き込む
      buffer.each_slice(@buffer_size) do |chunk|
        writer.write(WaveFile::Buffer.new(chunk, WaveFile::Format.new(:mono, :float, @sample_rate)))
      end
    end

    puts "Audio saved to #{@output_path}"
    @output_path
  end

  def clear_buffer
    @buffer = []
  end

  def get_buffer
    @buffer
  end
end
