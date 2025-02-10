class Step
  attr_accessor :active, :note, :velocity

  def initialize(active: false, note: "C4", velocity: 127)
    @active = active
    @note = note
    @velocity = velocity
  end
end
