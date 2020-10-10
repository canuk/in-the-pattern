require './app'
require './middlewares/in_the_pattern_middleware'

use InThePattern::InThePatternBackend

run InThePattern::App
