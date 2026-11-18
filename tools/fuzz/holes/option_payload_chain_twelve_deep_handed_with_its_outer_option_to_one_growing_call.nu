// option_payload_chain_twelve_deep_handed_with_its_outer_option_to_one_growing_call: AGORA-842 review (CodeRabbit on github#1967) — a slice of the innermost payload of 12 nested options, handed to one call with the outermost option that call grows the payload through
// AGORA-842: refused - the alias check follows the cursor chain to its end, however deep (no fixed hop count bounds it)
// map: §2.10 | A2 | rejected | - | AGORA-842
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ wr inout ? ? ? ? ? ? ? ? ? ? ? ? ( Vec i ) o ( Slice i ) sl → v {
    ?? o {
        T o12 → {
            ?? o12 {
                T o11 → {
                    ?? o11 {
                        T o10 → {
                            ?? o10 {
                                T o9 → {
                                    ?? o9 {
                                        T o8 → {
                                            ?? o8 {
                                                T o7 → {
                                                    ?? o7 {
                                                        T o6 → {
                                                            ?? o6 {
                                                                T o5 → {
                                                                    ?? o5 {
                                                                        T o4 → {
                                                                            ?? o4 {
                                                                                T o3 → {
                                                                                    ?? o3 {
                                                                                        T o2 → {
                                                                                            ?? o2 {
                                                                                                T q → {
                                                                                                    : ~ i k 0 ~ < k 1000 { ( vec_push [i] q k ) = k + k 1 }
                                                                                                }
                                                                                                F → {}
                                                                                            }
                                                                                        }
                                                                                        F → {}
                                                                                    }
                                                                                }
                                                                                F → {}
                                                                            }
                                                                        }
                                                                        F → {}
                                                                    }
                                                                }
                                                                F → {}
                                                            }
                                                        }
                                                        F → {}
                                                    }
                                                }
                                                F → {}
                                            }
                                        }
                                        F → {}
                                    }
                                }
                                F → {}
                            }
                        }
                        F → {}
                    }
                }
                F → {}
            }
        }
        F → {}
    }
    ( nurl_println_int ( slice_at [i] sl 1 ) )
}

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 1 )
    ( vec_push [i] xs 2 )
    : ~ ? ? ? ? ? ? ? ? ? ? ? ? ( Vec i ) o @ ?? ? ? ? ? ? ? ? ? ? ? ( Vec i ) { T @ ?? ? ? ? ? ? ? ? ? ? ( Vec i ) { T @ ?? ? ? ? ? ? ? ? ? ( Vec i ) { T @ ?? ? ? ? ? ? ? ? ( Vec i ) { T @ ?? ? ? ? ? ? ? ( Vec i ) { T @ ?? ? ? ? ? ? ( Vec i ) { T @ ?? ? ? ? ? ( Vec i ) { T @ ?? ? ? ? ( Vec i ) { T @ ?? ? ? ( Vec i ) { T @ ?? ? ( Vec i ) { T @ ?? ( Vec i ) { T @ ?( Vec i ) { T xs } } } } } } } } } } } }
    ?? o {
        T o12 → {
            ?? o12 {
                T o11 → {
                    ?? o11 {
                        T o10 → {
                            ?? o10 {
                                T o9 → {
                                    ?? o9 {
                                        T o8 → {
                                            ?? o8 {
                                                T o7 → {
                                                    ?? o7 {
                                                        T o6 → {
                                                            ?? o6 {
                                                                T o5 → {
                                                                    ?? o5 {
                                                                        T o4 → {
                                                                            ?? o4 {
                                                                                T o3 → {
                                                                                    ?? o3 {
                                                                                        T o2 → {
                                                                                            ?? o2 {
                                                                                                T q → {
                                                                                                    : ( Slice i ) sl ( slice_from_vec [i] q )
                                                                                                    ( wr o sl )
                                                                                                }
                                                                                                F → {}
                                                                                            }
                                                                                        }
                                                                                        F → {}
                                                                                    }
                                                                                }
                                                                                F → {}
                                                                            }
                                                                        }
                                                                        F → {}
                                                                    }
                                                                }
                                                                F → {}
                                                            }
                                                        }
                                                        F → {}
                                                    }
                                                }
                                                F → {}
                                            }
                                        }
                                        F → {}
                                    }
                                }
                                F → {}
                            }
                        }
                        F → {}
                    }
                }
                F → {}
            }
        }
        F → {}
    }
    ^ 0
}
