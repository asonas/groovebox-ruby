#include <stdio.h>
#include "pico/stdlib.h"
#include "picoruby.h"

int main()
{
  // Initialize stdio for USB output
  stdio_init_all();

  // Wait a moment for the USB to initialize
  sleep_ms(2000);

  printf("Starting PicoRuby Sequencer...\n");

  // Initialize PicoRuby VM
  mrb_state *mrb = picoruby_init();

  // Run the embedded Ruby code (main.rb)
  picoruby_run_mrb(mrb);

  // This code should never be reached as the Ruby code runs in an infinite loop
  printf("Ruby execution ended (this should not happen)\n");

  // Cleanup
  mrb_close(mrb);

  return 0;
}
