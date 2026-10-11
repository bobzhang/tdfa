///|
pub extend Regex with Add::{add}

///|
pub extend Regex with BitOr::{lor}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend MatchResult with @debug.Debug::{to_repr}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend Regex with @debug.Debug::{to_repr}
