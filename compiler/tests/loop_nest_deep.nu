// agora #210: the borrow checker walked a `~` body three or four times at
// every level of nesting, so 15 nested loops took 33 s to compile and 20
// went past any timeout. The loop fixpoint now converges over the walk's
// facts and repeats no walk: this nest of 40, each level giving `s` a new
// value, compiles in milliseconds. The runner's compile timeout is the
// regression check.
$ `stdlib/core/string.nu`

@ main → i {
    : ~ String s ( string_from `a` )
    : ~ i n 0
    ~ < n 1 {
        = s ( string_from `b` )
        ~ F {
            = s ( string_from `c` )
            ~ F {
                = s ( string_from `c` )
                ~ F {
                    = s ( string_from `c` )
                    ~ F {
                        = s ( string_from `c` )
                        ~ F {
                            = s ( string_from `c` )
                            ~ F {
                                = s ( string_from `c` )
                                ~ F {
                                    = s ( string_from `c` )
                                    ~ F {
                                        = s ( string_from `c` )
                                        ~ F {
                                            = s ( string_from `c` )
                                            ~ F {
                                                = s ( string_from `c` )
                                                ~ F {
                                                    = s ( string_from `c` )
                                                    ~ F {
                                                        = s ( string_from `c` )
                                                        ~ F {
                                                            = s ( string_from `c` )
                                                            ~ F {
                                                                = s ( string_from `c` )
                                                                ~ F {
                                                                    = s ( string_from `c` )
                                                                    ~ F {
                                                                        = s ( string_from `c` )
                                                                        ~ F {
                                                                            = s ( string_from `c` )
                                                                            ~ F {
                                                                                = s ( string_from `c` )
                                                                                ~ F {
                                                                                    = s ( string_from `c` )
                                                                                    ~ F {
                                                                                        = s ( string_from `c` )
                                                                                        ~ F {
                                                                                            = s ( string_from `c` )
                                                                                            ~ F {
                                                                                                = s ( string_from `c` )
                                                                                                ~ F {
                                                                                                    = s ( string_from `c` )
                                                                                                    ~ F {
                                                                                                        = s ( string_from `c` )
                                                                                                        ~ F {
                                                                                                            = s ( string_from `c` )
                                                                                                            ~ F {
                                                                                                                = s ( string_from `c` )
                                                                                                                ~ F {
                                                                                                                    = s ( string_from `c` )
                                                                                                                    ~ F {
                                                                                                                        = s ( string_from `c` )
                                                                                                                        ~ F {
                                                                                                                            = s ( string_from `c` )
                                                                                                                            ~ F {
                                                                                                                                = s ( string_from `c` )
                                                                                                                                ~ F {
                                                                                                                                    = s ( string_from `c` )
                                                                                                                                    ~ F {
                                                                                                                                        = s ( string_from `c` )
                                                                                                                                        ~ F {
                                                                                                                                            = s ( string_from `c` )
                                                                                                                                            ~ F {
                                                                                                                                                = s ( string_from `c` )
                                                                                                                                                ~ F {
                                                                                                                                                    = s ( string_from `c` )
                                                                                                                                                    ~ F {
                                                                                                                                                        = s ( string_from `c` )
                                                                                                                                                        ~ F {
                                                                                                                                                            = s ( string_from `c` )
                                                                                                                                                            ~ F {
                                                                                                                                                                = s ( string_from `c` )
                                                                                                                                                                ~ F {
                                                                                                                                                                    = s ( string_from `c` )
                                                                                                                                                                    ~ F {
                                                                                                                                                                        = s ( string_from `c` )
                                                                                                                                                                        : i z 1
                                                                                                                                                                    }
                                                                                                                                                                }
                                                                                                                                                            }
                                                                                                                                                        }
                                                                                                                                                    }
                                                                                                                                                }
                                                                                                                                            }
                                                                                                                                        }
                                                                                                                                    }
                                                                                                                                }
                                                                                                                            }
                                                                                                                        }
                                                                                                                    }
                                                                                                                }
                                                                                                            }
                                                                                                        }
                                                                                                    }
                                                                                                }
                                                                                            }
                                                                                        }
                                                                                    }
                                                                                }
                                                                            }
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        = n + n 1
    }
    ( nurl_println ( string_data s ) )
    ^ 0
}
