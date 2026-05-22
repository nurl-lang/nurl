extern "audio" fn level() f64;
extern "audio" fn bin(i: i64) f64;
extern "audio" fn bin_count() i64;
extern "audio" fn peak_bin() i64;
extern "audio" fn centroid() f64;
extern "audio" fn freq_of(i: i64) f64;
extern "audio" fn sample_rate() f64;
extern "audio" fn is_silent(threshold_pct: i64) i64;
extern "audio" fn ready() i64;

pub export fn audio_level() f64 {
    return level();
}

pub export fn audio_bin(i: i64) f64 {
    return bin(i);
}

pub export fn audio_bin_count() i64 {
    return bin_count();
}

pub export fn audio_peak_bin() i64 {
    return peak_bin();
}

pub export fn audio_centroid() f64 {
    return centroid();
}

pub export fn audio_freq_of(i: i64) f64 {
    return freq_of(i);
}

pub export fn audio_sample_rate() f64 {
    return sample_rate();
}

pub export fn audio_is_silent(threshold_pct: i64) i64 {
    return is_silent(threshold_pct);
}

pub export fn audio_ready() i64 {
    return ready();
}
