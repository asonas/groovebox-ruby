class VCA < FFI::PortAudio::Stream
  include FFI::PortAudio

  def initialize(generator, sample_rate, buffer_size)
    @generator = generator
    @buffer_size = buffer_size

    output_params = API::PaStreamParameters.new
    output_params[:device] = API.Pa_GetDefaultOutputDevice
    output_params[:channelCount] = 1
    output_params[:sampleFormat] = API::Float32
    output_params[:suggestedLatency] = API.Pa_GetDeviceInfo(output_params[:device])[:defaultHighOutputLatency]
    output_params[:hostApiSpecificStreamInfo] = nil

    super()
    open(nil, output_params, sample_rate, buffer_size)
    start
  end

  def process(input, output, frame_count, time_info, status_flags, user_data)
    samples = @generator.generate(frame_count)
    output.write_array_of_float(samples)
    :paContinue
  end
end
