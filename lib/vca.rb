require 'ffi-portaudio'
class VCA < FFI::PortAudio::Stream
  include FFI::PortAudio

  def initialize(generator, sample_rate, buffer_size)
    @generator = generator
    @buffer_size = buffer_size

    output_params = API::PaStreamParameters.new
    output_params[:device] = API.Pa_GetDefaultOutputDevice
    output_params[:channelCount] = 2
    output_params[:sampleFormat] = API::Float32
    output_params[:suggestedLatency] = API.Pa_GetDeviceInfo(output_params[:device])[:defaultHighOutputLatency]
    output_params[:hostApiSpecificStreamInfo] = nil

    super()
    open(nil, output_params, sample_rate, buffer_size)
    start
  end

  def process(input, output, frame_count, time_info, status_flags, user_data)
    samples = @generator.generate(frame_count)

    stereo_samples = []
    # TODO: PANの実装をするときはgenerateの中でsampleを左右に分ける
    samples.each do |sample|
      stereo_samples << sample # left
      stereo_samples << sample # right
    end

    output.write_array_of_float(stereo_samples)
    :paContinue
  end
end
