// sources_test.nu — data sources: a WFS read, pivoted, configured,
// scheduled and served.
//
//   wfs      — URLs (base, percent-encoding, the window's own times),
//              the catalogue from DescribeStoredQueries, the pivot of a
//              GetFeature answer (one row per location and time, NaN
//              dropped, the clock read), and what an exception becomes.
//   sources  — a record created with defaults, validated, listed,
//              changed (a new query resets the fetched span), deleted.
//   windows  — the first run, the next run, a backfill.
//   run      — fixture rows through the run path: points in the model
//              with their own timestamps, the span recorded, a second
//              run over the same window taking nothing, a backfill
//              taking only what lies before; an unreachable service
//              leaves an error on the record.
//   wide     — a GeoServer's capabilities as a catalogue of feature
//              types, GetFeature by type name, the wide pivot (one record
//              per feature, properties as numbers or text, the geometry's
//              coordinate, the clock from a date property or the fetch
//              time), and a feature-type source: its window, a categorical
//              coordinate stored as text.
//   http     — a JSON answer as records: an array at a path, an object as
//              a snapshot, nesting flattened, the clock detected; an HTTP
//              source with headers, masked on the way out and kept when
//              the mask comes back.
//   due      — what the scheduler would run and when.
//   routes   — the HTTP surface through router_handle, no sockets.
// Store root: $ANOMALY_TEST_DIR (default ./anomaly_sources_test).

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_router.nu`
$ `src/store.nu`
$ `src/dynamic.nu`
$ `src/wfs.nu`
$ `src/httpsrc.nu`
$ `src/sources.nu`
$ `src/service.nu`

: ~ i g_pass 0
: ~ i g_fail 0
: s ORG `public`
: i T_0500 1788757200
: i T_0600 1788760800

@ check b cond s label → v {
    ? cond {
        ( nurl_print `ok ` ) ( nurl_print label ) ( nurl_print `\n` )
        = g_pass + g_pass 1
    } {
        ( nurl_print `FAIL ` ) ( nurl_print label ) ( nurl_print `\n` )
        = g_fail + g_fail 1
    }
}

@ seq s a s b → b { ^ == ( nurl_str_eq a b ) 1 }

@ jstr Json o s key → s {
    ?? ( json_obj_get o key ) {
        T v → { ? ( json_is_str v ) { ^ ( json_str_data v ) } {} }
        F _ → {}
    }
    ^ ``
}

@ jbool Json o s key → b {
    ?? ( json_obj_get o key ) { T v → { ^ ( json_as_bool v ) } F _ → { ^ F } }
}

@ jfloat Json o s key → f {
    ?? ( json_obj_get o key ) { T v → { ?? ( json_num_as_f v ) { T x → { ^ x } F _ → { ^ 0.0 } } } F _ → { ^ 0.0 } }
}

@ near f a f b → b { ^ < ( float_abs - a b ) 0.000001 }

@ jint Json o s key → i {
    ?? ( json_obj_get o key ) {
        T v → { ? ( json_is_num v ) { ^ ( json_as_int v ) } {} }
        F _ → {}
    }
    ^ -1
}

@ jhas Json o s key → b { ^ ( json_obj_has o key ) }

@ has_col ( Vec String ) cols s name → b {
    : i n ( vec_len [String] cols )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] cols k ) {
            T c → { ? ( seq ( string_data c ) name ) { ^ T } {} }
            F _ → {}
        }
        = k + k 1
    }
    ^ F
}

// ── Fixtures ──────────────────────────────────────────────────────────

: s CATALOG_XML `<?xml version="1.0" encoding="UTF-8"?>
<DescribeStoredQueriesResponse xmlns="http://www.opengis.net/wfs/2.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <StoredQueryDescription id="fmi::observations::weather::simple">
    <Title>Instantaneous Weather Observations</Title>
    <Abstract>
    Real time weather observations from weather stations.
    </Abstract>
    <Parameter name="starttime" type="dateTime">
      <Title>Begin of the time interval</Title>
    </Parameter>
    <Parameter name="place" type="xsi:string">
      <Title>The location for which to provide data</Title>
      <Abstract>Region can be given after location name separated by comma.</Abstract>
    </Parameter>
    <Parameter name="timestep" type="int">
      <Title>The time step of data in minutes</Title>
    </Parameter>
  </StoredQueryDescription>
  <StoredQueryDescription id="fmi::observations::mareograph::simple">
    <Title>Sea level observations</Title>
    <Abstract>Sea level.</Abstract>
  </StoredQueryDescription>
</DescribeStoredQueriesResponse>`

: s FEATURE_XML `<?xml version="1.0" encoding="UTF-8"?>
<wfs:FeatureCollection timeStamp="2026-09-07T05:12:36Z" numberReturned="5" numberMatched="5"
    xmlns:wfs="http://www.opengis.net/wfs/2.0" xmlns:gml="http://www.opengis.net/gml/3.2"
    xmlns:BsWfs="http://xml.fmi.fi/schema/wfs/2.0">
  <wfs:member>
    <BsWfs:BsWfsElement gml:id="BsWfsElement.1.1.1">
      <BsWfs:Location>
        <gml:Point gml:id="P.1.1.1" srsDimension="2"><gml:pos>60.17523 24.94459 </gml:pos></gml:Point>
      </BsWfs:Location>
      <BsWfs:Time>2026-09-07T05:00:00Z</BsWfs:Time>
      <BsWfs:ParameterName>t2m</BsWfs:ParameterName>
      <BsWfs:ParameterValue>7.5</BsWfs:ParameterValue>
    </BsWfs:BsWfsElement>
  </wfs:member>
  <wfs:member>
    <BsWfs:BsWfsElement gml:id="BsWfsElement.1.1.2">
      <BsWfs:Location>
        <gml:Point gml:id="P.1.1.2" srsDimension="2"><gml:pos>60.17523 24.94459 </gml:pos></gml:Point>
      </BsWfs:Location>
      <BsWfs:Time>2026-09-07T05:00:00Z</BsWfs:Time>
      <BsWfs:ParameterName>ws_10min</BsWfs:ParameterName>
      <BsWfs:ParameterValue>1.6</BsWfs:ParameterValue>
    </BsWfs:BsWfsElement>
  </wfs:member>
  <wfs:member>
    <BsWfs:BsWfsElement gml:id="BsWfsElement.1.2.1">
      <BsWfs:Location>
        <gml:Point gml:id="P.1.2.1" srsDimension="2"><gml:pos>60.17523 24.94459 </gml:pos></gml:Point>
      </BsWfs:Location>
      <BsWfs:Time>2026-09-07T06:00:00Z</BsWfs:Time>
      <BsWfs:ParameterName>t2m</BsWfs:ParameterName>
      <BsWfs:ParameterValue>8.25</BsWfs:ParameterValue>
    </BsWfs:BsWfsElement>
  </wfs:member>
  <wfs:member>
    <BsWfs:BsWfsElement gml:id="BsWfsElement.1.2.2">
      <BsWfs:Location>
        <gml:Point gml:id="P.1.2.2" srsDimension="2"><gml:pos>60.17523 24.94459 </gml:pos></gml:Point>
      </BsWfs:Location>
      <BsWfs:Time>2026-09-07T06:00:00Z</BsWfs:Time>
      <BsWfs:ParameterName>ws_10min</BsWfs:ParameterName>
      <BsWfs:ParameterValue>NaN</BsWfs:ParameterValue>
    </BsWfs:BsWfsElement>
  </wfs:member>
  <wfs:member>
    <BsWfs:BsWfsElement gml:id="BsWfsElement.2.1.1">
      <BsWfs:Location>
        <gml:Point gml:id="P.2.1.1" srsDimension="2"><gml:pos>61.0 25.0</gml:pos></gml:Point>
      </BsWfs:Location>
      <BsWfs:Time>2026-09-07T05:00:00Z</BsWfs:Time>
      <BsWfs:ParameterName>t2m</BsWfs:ParameterName>
      <BsWfs:ParameterValue>-3</BsWfs:ParameterValue>
    </BsWfs:BsWfsElement>
  </wfs:member>
</wfs:FeatureCollection>`

: s EXCEPTION_XML `<?xml version="1.0" encoding="UTF-8"?>
<ExceptionReport xmlns="http://www.opengis.net/ows/1.1" version="2.0.0">
  <Exception exceptionCode="OperationParsingFailed">
    <ExceptionText>No location parameter given</ExceptionText>
  </Exception>
</ExceptionReport>`

: s CAPS_XML `<?xml version="1.0" encoding="UTF-8"?>
<wfs:WFS_Capabilities xmlns:wfs="http://www.opengis.net/wfs/2.0" xmlns:ows="http://www.opengis.net/ows/1.1" version="2.0.0">
  <ows:OperationsMetadata><ows:Operation name="GetFeature"/><ows:Operation name="DescribeStoredQueries"/></ows:OperationsMetadata>
  <FeatureTypeList>
    <FeatureType xmlns:dwd="https://www.dwd.de">
      <Name>dwd:RBSN_T2m</Name>
      <Title>2m Temperatur an RBSN Stationen</Title>
      <Abstract>Messwerte der 2m Temperatur.</Abstract>
      <DefaultCRS>urn:ogc:def:crs:EPSG::4258</DefaultCRS>
    </FeatureType>
    <FeatureType>
      <Name>ms:cities</Name>
      <Title>World cities</Title>
    </FeatureType>
  </FeatureTypeList>
</wfs:WFS_Capabilities>`

: s WIDE_XML `<?xml version="1.0" encoding="UTF-8"?>
<wfs:FeatureCollection xmlns:wfs="http://www.opengis.net/wfs/2.0" xmlns:gml="http://www.opengis.net/gml/3.2" xmlns:dwd="https://www.dwd.de" numberReturned="3">
  <wfs:member>
    <dwd:RBSN_T2m gml:id="RBSN_T2m.102">
      <gml:boundedBy><gml:Envelope srsName="urn:ogc:def:crs:EPSG::4258"><gml:lowerCorner>1 1</gml:lowerCorner><gml:upperCorner>2 2</gml:upperCorner></gml:Envelope></gml:boundedBy>
      <dwd:ID>102</dwd:ID>
      <dwd:NAME>Leuchtturm Alte Weser</dwd:NAME>
      <dwd:TEMPERATURE>17.5</dwd:TEMPERATURE>
      <dwd:M_DATE>2026-09-07T05:00:00Z</dwd:M_DATE>
      <dwd:THE_GEOM><gml:Point srsName="urn:ogc:def:crs:EPSG::4258"><gml:pos>53.8633 8.1275</gml:pos></gml:Point></dwd:THE_GEOM>
    </dwd:RBSN_T2m>
  </wfs:member>
  <wfs:member>
    <dwd:RBSN_T2m gml:id="RBSN_T2m.164">
      <dwd:ID>164</dwd:ID>
      <dwd:NAME>Angermünde</dwd:NAME>
      <dwd:TEMPERATURE>NaN</dwd:TEMPERATURE>
      <dwd:M_DATE>2026-09-07T06:00:00Z</dwd:M_DATE>
      <dwd:THE_GEOM><gml:Point><gml:pos>53.0316 13.9908</gml:pos></gml:Point></dwd:THE_GEOM>
    </dwd:RBSN_T2m>
  </wfs:member>
  <wfs:member>
    <dwd:RBSN_T2m gml:id="RBSN_T2m.183">
      <dwd:ID>183</dwd:ID>
      <dwd:NAME>Arkona</dwd:NAME>
      <dwd:TEMPERATURE>15.25</dwd:TEMPERATURE>
      <dwd:M_DATE>2026-09-07T06:00:00Z</dwd:M_DATE>
      <dwd:NOTE>some very long text</dwd:NOTE>
      <dwd:THE_GEOM><gml:Point><gml:pos>54.6791 13.4343</gml:pos></gml:Point></dwd:THE_GEOM>
    </dwd:RBSN_T2m>
  </wfs:member>
</wfs:FeatureCollection>`

: s SNAPSHOT_XML `<?xml version="1.0" encoding="UTF-8"?>
<wfs:FeatureCollection xmlns:wfs="http://www.opengis.net/wfs/2.0" xmlns:gml="http://www.opengis.net/gml/3.2" xmlns:ms="http://mapserver.gis.umn.edu/mapserver">
  <wfs:member>
    <ms:cities gml:id="cities.1">
      <ms:geom><gml:Point><gml:pos>48.85 2.35</gml:pos></gml:Point></ms:geom>
      <ms:NAME>Paris</ms:NAME>
      <ms:POPULATION>2140526</ms:POPULATION>
    </ms:cities>
  </wfs:member>
</wfs:FeatureCollection>`

: s JSON_ARRAY `{"status":"ok","data":{"items":[
  {"id":"st-1","name":"Kumpula","measured":"2026-09-07T05:00:00Z","reading":{"temperature":7.5,"humidity":82},"ok":true,"tags":["a","b"],"note":null},
  {"id":"st-2","name":"Kaisaniemi","measured":"2026-09-07T06:00:00Z","reading":{"temperature":8.25,"humidity":80},"ok":false},
  {"id":"st-3","name":"Harmaja","measured":"2026-09-07T06:00:00Z","reading":{"temperature":"NaN","humidity":90}}
]}}`

: s JSON_OBJECT `{"latitude":60.17,"longitude":24.94,"current":{"time":"2026-09-07T13:15","temperature_2m":18.3,"wind_speed_10m":9.4},"units":{"temperature_2m":"°C"}}`

: s EMPTY_FC_XML `<?xml version="1.0" encoding="UTF-8"?>
<wfs:FeatureCollection xmlns:wfs="http://www.opengis.net/wfs/2.0" numberReturned="0" numberMatched="0">
</wfs:FeatureCollection>`

// ── wfs ───────────────────────────────────────────────────────────────

@ test_wfs → v {
    : String b1 ( wfs_base_url ` https://opendata.fmi.fi/wfs?request=GetCapabilities ` )
    ( check ( seq ( string_data b1 ) `https://opendata.fmi.fi/wfs` ) `wfs: base url drops the query and the spaces` )
    ( string_free b1 )
    : String b2 ( wfs_base_url `http://example.org/wfs` )
    ( check ( seq ( string_data b2 ) `http://example.org/wfs` ) `wfs: base url without a query stays` )
    ( string_free b2 )
    ( check ( wfs_url_ok `https://opendata.fmi.fi/wfs?request=GetCapabilities` ) `wfs: https url ok` )
    ( check ! ( wfs_url_ok `ftp://opendata.fmi.fi/wfs` ) `wfs: ftp refused` )
    ( check ! ( wfs_url_ok `` ) `wfs: empty refused` )

    : String cu ( wfs_url_catalog `https://opendata.fmi.fi/wfs?x=1` )
    ( check ( seq ( string_data cu ) `https://opendata.fmi.fi/wfs?service=WFS&version=2.0.0&request=DescribeStoredQueries` ) `wfs: catalogue url` )
    ( string_free cu )

    : Json params ( json_obj_new )
    ( json_obj_set params `place` ( json_str_lit `Kumpula,Helsinki` ) )
    ( json_obj_set params `timestep` ( json_int 60 ) )
    ( json_obj_set params `starttime` ( json_str_lit `2001-01-01T00:00:00Z` ) )
    ( json_obj_set params `crs` ( json_str_lit `` ) )
    : String fu ( wfs_url_feature `https://opendata.fmi.fi/wfs` `fmi::observations::weather::simple` params T_0500 T_0600 )
    ( check ( string_contains fu `request=GetFeature&storedquery_id=fmi%3A%3Aobservations%3A%3Aweather%3A%3Asimple` ) `wfs: feature url names the query, encoded` )
    ( check ( string_contains fu `&place=Kumpula%2CHelsinki` ) `wfs: feature url encodes the comma` )
    ( check ( string_contains fu `&timestep=60` ) `wfs: a numeric parameter prints as an integer` )
    ( check ! ( string_contains fu `2001-01-01` ) `wfs: a saved starttime is not sent` )
    ( check ! ( string_contains fu `crs=` ) `wfs: an empty parameter is not sent` )
    ( check ( string_contains fu `&starttime=2026-09-07T05%3A00%3A00Z&endtime=2026-09-07T06%3A00%3A00Z` ) `wfs: the window's times end the url` )
    ( string_free fu )
    ( json_free params )

    : Json cat ( wfs_catalog CATALOG_XML )
    ( check ! ( jhas cat `error` ) `wfs: catalogue parses` )
    ?? ( json_obj_get cat `queries` ) {
        T qs → {
            ( check == ( json_arr_len qs ) 2 `wfs: two stored queries` )
            ?? ( json_arr_get qs 0 ) {
                T q → {
                    ( check ( seq ( jstr q `id` ) `fmi::observations::weather::simple` ) `wfs: query id` )
                    ( check ( seq ( jstr q `title` ) `Instantaneous Weather Observations` ) `wfs: query title` )
                    ( check ( starts_text ( jstr q `abstract` ) `Real time` ) `wfs: abstract trimmed` )
                    ?? ( json_obj_get q `parameters` ) {
                        T ps → {
                            ( check == ( json_arr_len ps ) 3 `wfs: three parameters` )
                            ?? ( json_arr_get ps 1 ) {
                                T pp → {
                                    ( check ( seq ( jstr pp `name` ) `place` ) `wfs: parameter name` )
                                    ( check ( seq ( jstr pp `type` ) `xsi:string` ) `wfs: parameter type` )
                                    ( check ( seq ( jstr pp `title` ) `The location for which to provide data` ) `wfs: parameter title` )
                                }
                                F _ → { ( check F `wfs: parameter 1` ) }
                            }
                        }
                        F _ → { ( check F `wfs: parameters` ) }
                    }
                }
                F _ → { ( check F `wfs: query 0` ) }
            }
        }
        F _ → { ( check F `wfs: queries` ) }
    }
    ( json_free cat )
    : Json cat2 ( wfs_catalog EXCEPTION_XML )
    ( check ( has_text ( jstr cat2 `error` ) `exception` ) `wfs: an exception report is an error` )
    ( json_free cat2 )
    : Json cat3 ( wfs_catalog `this is not xml` )
    ( check ( jhas cat3 `error` ) `wfs: garbage is an error` )
    ( json_free cat3 )

    : WfsPivot pv ( wfs_pivot FEATURE_XML )
    ( check == ( string_len . pv err ) 0 `pivot: no error` )
    ( check == . pv members 5 `pivot: five members read` )
    ( check == ( vec_len [Json] . pv rows ) 3 `pivot: three (location, time) rows` )
    ( check == . pv missing 1 `pivot: one NaN left out` )
    ( check ( has_col . pv columns `lat` ) `pivot: lat column` )
    ( check ( has_col . pv columns `t2m` ) `pivot: t2m column` )
    ( check ( has_col . pv columns `ws_10min` ) `pivot: ws_10min column` )
    ( check == ( vec_len [String] . pv columns ) 4 `pivot: four columns` )
    ?? ( vec_get [Json] . pv rows 0 ) {
        T r0 → {
            ( check == ( jint r0 `timestamp` ) T_0500 `pivot: row 0 clock read` )
            ( check ( seq ( jstr r0 `time` ) `2026-09-07T05:00:00Z` ) `pivot: row 0 keeps the ISO time` )
            ( check ( jhas r0 `ws_10min` ) `pivot: row 0 has wind` )
        }
        F _ → { ( check F `pivot: row 0` ) }
    }
    ?? ( vec_get [Json] . pv rows 1 ) {
        T r1 → {
            ( check == ( jint r1 `timestamp` ) T_0600 `pivot: row 1 is the next hour` )
            ( check ! ( jhas r1 `ws_10min` ) `pivot: row 1 lacks the NaN wind` )
            ( check ( jhas r1 `t2m` ) `pivot: row 1 has t2m` )
        }
        F _ → { ( check F `pivot: row 1` ) }
    }
    ?? ( vec_get [Json] . pv rows 2 ) {
        T r2 → {
            ( check == ( jint r2 `timestamp` ) T_0500 `pivot: row 2 is the other station at 05:00` )
            ( check == ( jint r2 `t2m` ) -3 `pivot: row 2 negative value` )
        }
        F _ → { ( check F `pivot: row 2` ) }
    }
    ( wfs_pivot_free pv )
    : WfsPivot pe ( wfs_pivot EXCEPTION_XML )
    ( check ( string_contains . pe err `No location parameter given` ) `pivot: exception text surfaces` )
    ( wfs_pivot_free pe )
    : WfsPivot pf ( wfs_pivot EMPTY_FC_XML )
    ( check ( string_starts_with . pf err `the feature collection holds no` ) `pivot: an empty collection says so` )
    ( check == ( vec_len [Json] . pf rows ) 0 `pivot: an empty collection has no rows` )
    ( wfs_pivot_free pf )
    : WfsPivot pg ( wfs_pivot `<html>nope</html>` )
    ( check ( seq ( string_data . pg err ) `not a WFS feature collection` ) `pivot: another document is refused` )
    ( wfs_pivot_free pg )
}

// ── sources ───────────────────────────────────────────────────────────

@ body_full → Json {
    : Json b ( json_obj_new )
    ( json_obj_set b `url` ( json_str_lit `https://opendata.fmi.fi/wfs?request=GetCapabilities` ) )
    ( json_obj_set b `query` ( json_str_lit `fmi::observations::weather::simple` ) )
    : Json p ( json_obj_new )
    ( json_obj_set p `place` ( json_str_lit `Helsinki` ) )
    ( json_obj_set p `timestep` ( json_int 60 ) )
    ( json_obj_set b `params` p )
    : Json f ( json_arr_new )
    ( json_arr_push f ( json_str_lit `t2m` ) )
    ( json_arr_push f ( json_str_lit `ws_10min` ) )
    ( json_obj_set b `features` f )
    ( json_obj_set b `model` ( json_str_lit `helsinki_weather` ) )
    ^ b
}

// Create; returns the id (owned).
@ make_source → String {
    : Json b ( body_full )
    : ~ String id ( string_new )
    ?? ( source_create ORG b `tester` 1000 ) {
        T src → { ( string_free id ) = id ( string_from ( jstr src `id` ) ) ( json_free src ) }
        F e → { ( string_free e ) }
    }
    ( json_free b )
    ^ id
}

@ test_sources → v {
    : Json b ( body_full )
    : ~ String id ( string_new )
    ?? ( source_create ORG b `tester` 1000 ) {
        T src → {
            ( string_free id )
            = id ( string_from ( jstr src `id` ) )
            ( check ( source_id_ok ( string_data id ) ) `sources: id is twelve hex digits` )
            ( check ( seq ( jstr src `url` ) `https://opendata.fmi.fi/wfs` ) `sources: url stored as its base` )
            ( check ( seq ( jstr src `name` ) `fmi::observations::weather::simple` ) `sources: nameless → named after the query` )
            ( check == ( jint src `interval_minutes` ) 10 `sources: default interval` )
            ( check == ( jint src `history_hours` ) 168 `sources: default history is a week` )
            ( check ! ( jbool src `allow_future` ) `sources: nothing from the future by default` )
            ( check ( near ( jfloat src `finetune_rate` ) 0.01 ) `sources: the first train calibrates to 1 %` )
            ( check == ( jint src `created_at` ) 1000 `sources: created_at` )
            ( check ( seq ( jstr src `created_by` ) `tester` ) `sources: created_by` )
            ( check ( seq ( jstr src `kind` ) `wfs` ) `sources: kind` )
            ( check == ( jint src `last_time` ) 0 `sources: nothing fetched yet` )
            ( json_free src )
        }
        F e → { ( nurl_print `  create said: ` ) ( nurl_print ( string_data e ) ) ( nurl_print `\n` ) ( check F `sources: create` ) ( string_free e ) }
    }
    ( json_free b )

    // What is refused.
    : Json bad1 ( body_full )
    ( json_obj_set bad1 `url` ( json_str_lit `ftp://x/wfs` ) )
    ?? ( source_create ORG bad1 `tester` 1000 ) {
        T s1 → { ( check F `sources: ftp url refused` ) ( json_free s1 ) }
        F e → { ( check ( string_contains e `url must be` ) `sources: ftp url refused` ) ( string_free e ) }
    }
    ( json_free bad1 )
    : Json bad2 ( json_obj_new )
    ( json_obj_set bad2 `url` ( json_str_lit `https://opendata.fmi.fi/wfs` ) )
    ?? ( source_create ORG bad2 `tester` 1000 ) {
        T s2 → { ( check F `sources: missing query and model refused` ) ( json_free s2 ) }
        F e → { ( check ( string_contains e `needs url, query and model` ) `sources: missing query and model refused` ) ( string_free e ) }
    }
    ( json_free bad2 )
    : Json bad3 ( body_full )
    ( json_obj_set bad3 `interval_minutes` ( json_int 0 ) )
    ?? ( source_create ORG bad3 `tester` 1000 ) {
        T s3 → { ( check F `sources: interval 0 refused` ) ( json_free s3 ) }
        F e → { ( check ( string_contains e `interval_minutes` ) `sources: interval 0 refused` ) ( string_free e ) }
    }
    ( json_free bad3 )
    : Json bad4 ( body_full )
    ( json_obj_set bad4 `model` ( json_str_lit `no spaces` ) )
    ?? ( source_create ORG bad4 `tester` 1000 ) {
        T s4 → { ( check F `sources: bad model name refused` ) ( json_free s4 ) }
        F e → { ( check ( string_contains e `model must be` ) `sources: bad model name refused` ) ( string_free e ) }
    }
    ( json_free bad4 )
    : Json bad5 ( body_full )
    ( json_obj_set bad5 `features` ( json_str_lit `t2m` ) )
    ?? ( source_create ORG bad5 `tester` 1000 ) {
        T s5 → { ( check F `sources: features must be an array` ) ( json_free s5 ) }
        F e → { ( check ( string_contains e `features must be` ) `sources: features must be an array` ) ( string_free e ) }
    }
    ( json_free bad5 )

    : ( Vec Json ) all ( sources_list ORG )
    ( check == ( vec_len [Json] all ) 1 `sources: one listed` )
    ( sources_free all )

    // Change the interval: the span stays. Change the query: it resets.
    ?? ( source_load ORG ( string_data id ) ) {
        T src → {
            ( json_obj_set src `first_time` ( json_int 500 ) )
            ( json_obj_set src `last_time` ( json_int 900 ) )
            ( check ( source_save ORG src ) `sources: saved with a span` )
            ( json_free src )
        }
        F _ → { ( check F `sources: load` ) }
    }
    : Json ch1 ( json_obj_new )
    ( json_obj_set ch1 `interval_minutes` ( json_int 30 ) )
    ( json_obj_set ch1 `name` ( json_str_lit `  Helsinki hourly  ` ) )
    ?? ( source_update ORG ( string_data id ) ch1 2000 ) {
        T src → {
            ( check == ( jint src `interval_minutes` ) 30 `sources: interval changed` )
            ( check ( seq ( jstr src `name` ) `Helsinki hourly` ) `sources: name trimmed` )
            ( check == ( jint src `last_time` ) 900 `sources: the span survives an interval change` )
            ( check == ( jint src `updated_at` ) 2000 `sources: updated_at` )
            ( json_free src )
        }
        F e → { ( check F `sources: update interval` ) ( string_free e ) }
    }
    ( json_free ch1 )
    : Json ch2 ( json_obj_new )
    ( json_obj_set ch2 `query` ( json_str_lit `fmi::observations::weather::hourly::simple` ) )
    ?? ( source_update ORG ( string_data id ) ch2 2100 ) {
        T src → {
            ( check == ( jint src `last_time` ) 0 `sources: a new query resets the span` )
            ( check == ( jint src `first_time` ) 0 `sources: a new query resets first_time` )
            ( json_free src )
        }
        F e → { ( check F `sources: update query` ) ( string_free e ) }
    }
    ( json_free ch2 )
    : Json ch3 ( json_obj_new )
    ( json_obj_set ch3 `history_hours` ( json_int 99999 ) )
    ?? ( source_update ORG ( string_data id ) ch3 2200 ) {
        T src → { ( check F `sources: absurd history refused` ) ( json_free src ) }
        F e → { ( check ( string_contains e `history_hours` ) `sources: absurd history refused` ) ( string_free e ) }
    }
    ?? ( source_update ORG `000000000000` ch3 2200 ) {
        T src → { ( check F `sources: unknown id` ) ( json_free src ) }
        F e → { ( check ( seq ( string_data e ) `no such source` ) `sources: unknown id` ) ( string_free e ) }
    }
    ( json_free ch3 )

    ( check ( source_delete ORG ( string_data id ) ) `sources: deleted` )
    ( check ! ( source_delete ORG ( string_data id ) ) `sources: deleting twice is false` )
    : ( Vec Json ) none ( sources_list ORG )
    ( check == ( vec_len [Json] none ) 0 `sources: none listed after delete` )
    ( sources_free none )
    ( string_free id )
}

// ── windows ───────────────────────────────────────────────────────────

@ test_windows → v {
    : Json src ( json_obj_new )
    ( json_obj_set src `history_hours` ( json_int 6 ) )
    : i now 1000000
    : SrcWindow w1 ( source_window src now F 0 )
    ( check & == . w1 start - now 21600 == . w1 end now `window: first run reaches history_hours back` )
    ( json_obj_set src `first_time` ( json_int - now 21600 ) )
    ( json_obj_set src `last_time` ( json_int - now 600 ) )
    : SrcWindow w2 ( source_window src now F 0 )
    ( check & == . w2 start + - now 600 1 == . w2 end now `window: the next run starts after last_time` )
    : SrcWindow w3 ( source_window src now T 48 )
    ( check & == . w3 start - now 172800 == . w3 end - - now 21600 1 `window: a backfill ends before first_time` )
    : SrcWindow w4 ( source_window src now T 1 )
    ( check > . w4 start . w4 end `window: a backfill inside the span is empty` )
    ( json_free src )

    // The step of a run's points and the season it implies.
    : ( Vec Json ) pts ( vec_new [Json] )
    : ~ i k 0
    ~ < k 20 {
        : Json p ( json_obj_new )
        ( json_obj_set p `timestamp` ( json_int + 1000000 * k 600 ) )
        ( vec_push [Json] pts p )
        = k + k 1
    }
    ( check == ( source_step_of pts ) 600 `step: ten minutes` )
    ( check == ( source_season_of 600 ) 144 `season: ten minutes → 144 rows a day` )
    ( check == ( source_season_of 3600 ) 24 `season: an hour → 24` )
    ( check == ( source_season_of 86400 ) 7 `season: a day → the week` )
    ( check == ( source_season_of 0 ) 0 `season: no step, no season` )
    ( check == ( source_season_of 200000 ) 0 `season: a step past a day has none` )
    ( vec_free_with [Json] pts \ Json j → v { ( json_free j ) } )
}

// The first train of a model that arrived as a whole calibrates its
// margins once; a second call, and a later run, leave them alone.
@ test_autotune Store st → v {
    : *Model mo ( model_open_at st `tuned` 1000 )
    ( model_set_limits mo 10 150000 )
    ( model_set_schedule mo 100000 100000 )
    : ~ i k 0
    : ~ i seed 5
    ~ < k 120 {
        = seed % + * seed 1103515245 12345 2147483648
        : Json j ( json_obj_new )
        ( json_obj_set j `t` ( json_float + 20.0 / # f % seed 1000 100.0 ) )
        ( json_obj_set j `p` ( json_float + 1000.0 / # f % + seed 77 1000 50.0 ) )
        : !Verdict String r ( model_ingest_at mo j + 1000 * k 60 )
        ?? r { T vd → { ( verdict_free vd ) } F e → { ( string_free e ) } }
        ( json_free j )
        = k + k 1
    }
    : i tr ( model_force_train_at mo + 1000 * 120 60 )
    ( check > tr 0 `autotune: trained` )
    : *Meta mm ( model_metadata mo )
    ( check == . mm tuned_at 0 `autotune: never tuned yet` )
    : f before ( meta_version_margin mm `short_term` -1.0 )
    ( check ! ( model_autotune_at mo 0.005 9998 ) `autotune: a rate that would flag no row of 120 does nothing` )
    ( check == . mm tuned_at 0 `autotune: and leaves the model untuned for a bigger ring` )
    ( check ( model_autotune_at mo 0.05 9999 ) `autotune: the first train calibrates` )
    ( check == . mm tuned_at 9999 `autotune: and remembers when` )
    : f after ( meta_version_margin mm `short_term` -1.0 )
    ( check ! ( near before after ) `autotune: the margin moved` )
    ( check ! ( model_autotune_at mo 0.05 10000 ) `autotune: a second call does nothing` )
    ( check == . mm tuned_at 9999 `autotune: the first time stands` )
    ( check ! ( model_autotune_at mo 0.0 10001 ) `autotune: rate 0 does nothing` )
    // the metadata carries it
    : String js ( meta_to_json_str mm )
    ?? ( meta_from_json_str ( string_data js ) ) {
        T m2 → { ( check == . m2 tuned_at 9999 `autotune: tuned_at survives the JSON round trip` ) ( meta_free m2 ) }
        F _ → { ( check F `autotune: metadata parses back` ) }
    }
    ( string_free js )
    ( model_free mo )
}

// ── run ───────────────────────────────────────────────────────────────

@ fixture_rows → ( Vec Json ) {
    : WfsPivot pv ( wfs_pivot FEATURE_XML )
    : ( Vec Json ) rows ( vec_new [Json] )
    : i n ( vec_len [Json] . pv rows )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [Json] . pv rows k ) {
            T r → { ( vec_push [Json] rows ( json_clone r ) ) }
            F _ → {}
        }
        = k + k 1
    }
    ( wfs_pivot_free pv )
    ^ rows
}

@ nop → v {}

@ test_run Store st → v {
    : String id ( make_source )
    ( check > ( string_len id ) 0 `run: source made` )
    : i now + T_0600 1800

    // A forward window over the fixture: three rows, two features each
    // except the one whose wind was NaN.
    : SrcWindow w @ SrcWindow { - T_0500 3600 now }
    : Json r1 ( source_run_rows ORG ( string_data id ) @ !( Vec Json ) String { T ( fixture_rows ) } w F now )
    ( check ( seq ( jstr r1 `status` ) `success` ) `run: success` )
    ( check == ( jint r1 `ingested` ) 3 `run: three points in` )
    ( check == ( jint r1 `fetched` ) 3 `run: three rows fetched` )
    ( check == ( jint r1 `newest` ) T_0600 `run: newest observation` )
    ( check == ( jint r1 `oldest` ) T_0500 `run: oldest observation` )
    ( json_free r1 )
    ?? ( source_load ORG ( string_data id ) ) {
        T src → {
            ( check ( seq ( jstr src `last_status` ) `ok` ) `run: record says ok` )
            ( check == ( jint src `last_time` ) now `run: last_time is the window's end` )
            ( check == ( jint src `first_time` ) - T_0500 3600 `run: first_time is the window's start` )
            ( check == ( jint src `last_rows` ) 3 `run: last_rows` )
            ( check == ( jint src `total_rows` ) 3 `run: total_rows` )
            ( check == ( jint src `runs` ) 1 `run: runs` )
            ( check == ( jint src `last_run` ) now `run: last_run` )
            ( json_free src )
        }
        F _ → { ( check F `run: reload` ) }
    }
    ( check ( store_exists st `helsinki_weather` ) `run: the model exists now` )
    : *Model mo ( model_open st `helsinki_weather` )
    ( check == ( model_n_points mo ) 3 `run: the model holds three points` )
    ( check == ( model_last_ts mo ) T_0600 `run: the newest point carries the observation's clock` )
    : *Meta mm . mo meta
    ( check ! . mm count_clock `run: a time clock` )
    ( model_free mo )

    // The same rows again, in the window the next run would ask for:
    // every row lies before it, so nothing lands twice.
    : SrcWindow w2 @ SrcWindow { + now 1 + now 600 }
    : Json r2 ( source_run_rows ORG ( string_data id ) @ !( Vec Json ) String { T ( fixture_rows ) } w2 F + now 600 )
    ( check ( seq ( jstr r2 `status` ) `success` ) `run: second run succeeds` )
    ( check == ( jint r2 `ingested` ) 0 `run: nothing ingested twice` )
    ( check == ( jint r2 `skipped_outside` ) 3 `run: the rows were outside the window` )
    ( json_free r2 )
    : *Model mo2 ( model_open st `helsinki_weather` )
    ( check == ( model_n_points mo2 ) 3 `run: still three points` )
    ( model_free mo2 )

    // A backfill window ending before first_time takes only what lies
    // there: nothing from this fixture, and first_time moves back.
    : SrcWindow w3 @ SrcWindow { - T_0500 7200 - - T_0500 3600 1 }
    : Json r3 ( source_run_rows ORG ( string_data id ) @ !( Vec Json ) String { T ( fixture_rows ) } w3 T + now 700 )
    ( check ( seq ( jstr r3 `status` ) `success` ) `run: backfill succeeds` )
    ( check == ( jint r3 `ingested` ) 0 `run: backfill takes nothing from inside the span` )
    ( json_free r3 )
    ?? ( source_load ORG ( string_data id ) ) {
        T src → {
            ( check == ( jint src `first_time` ) - T_0500 7200 `run: backfill moved first_time back` )
            ( check == ( jint src `last_time` ) + now 600 `run: last_time untouched by a backfill` )
            ( json_free src )
        }
        F _ → { ( check F `run: reload after backfill` ) }
    }

    // Only the chosen features land: lat and lon were not chosen.
    : *Model mo3 ( model_open st `helsinki_weather` )
    ?? ( vec_get [String] . mo3 lines 0 ) {
        T line → {
            ( check ( string_contains line `"t2m"` ) `run: t2m stored` )
            ( check ! ( string_contains line `"lat"` ) `run: lat not stored (not chosen)` )
            ( check ( string_contains line `"time"` ) `run: the ISO time kept for calendar features` )
        }
        F _ → { ( check F `run: stored line` ) }
    }
    ( model_free mo3 )

    // A fetch that fails leaves the error on the record and the model alone.
    : Json e1 ( source_run_rows ORG ( string_data id ) @ !( Vec Json ) String { F ( string_from `HTTP 400 from the service: bad place` ) } w F + now 800 )
    ( check ( seq ( jstr e1 `status` ) `error` ) `run: a failed fetch is an error` )
    ( check ( has_text ( jstr e1 `message` ) `HTTP 400` ) `run: the reason is passed on` )
    ( json_free e1 )
    ?? ( source_load ORG ( string_data id ) ) {
        T src → {
            ( check ( seq ( jstr src `last_status` ) `error` ) `run: record says error` )
            ( check ( has_text ( jstr src `last_error` ) `bad place` ) `run: last_error kept` )
            ( check == ( jint src `runs` ) 4 `run: every attempt counts as a run` )
            ( json_free src )
        }
        F _ → { ( check F `run: reload after error` ) }
    }

    // A source nobody can reach: the real path, with the lock closures,
    // ends in an error on the record within the connect failure.
    : Json ch ( json_obj_new )
    ( json_obj_set ch `url` ( json_str_lit `http://127.0.0.1:9/wfs` ) )
    ?? ( source_update ORG ( string_data id ) ch 3000 ) { T s → { ( json_free s ) } F e → { ( string_free e ) } }
    ( json_free ch )
    : Json e2 ( source_run ORG ( string_data id ) F 0 + now 900 \ → v { ( nop ) } \ → v { ( nop ) } )
    ( check ( seq ( jstr e2 `status` ) `error` ) `run: an unreachable service is an error` )
    ( check ( has_text ( jstr e2 `message` ) `could not fetch` ) `run: says it could not fetch` )
    ( check ! ( source_is_running ORG ( string_data id ) ) `run: not marked running afterwards` )
    ( json_free e2 )
    : Json e3 ( source_run ORG `000000000000` F 0 now \ → v { ( nop ) } \ → v { ( nop ) } )
    ( check ( seq ( jstr e3 `message` ) `no such source` ) `run: unknown source` )
    ( json_free e3 )

    // a changed model resets the span: the new model has seen none of it
    : Json chm ( json_obj_new )
    ( json_obj_set chm `model` ( json_str_lit `other_model` ) )
    ?? ( source_update ORG ( string_data id ) chm + now 5 ) {
        T upd → {
            ( check == ( jint upd `first_time` ) 0 `run: a changed model resets first_time` )
            ( check == ( jint upd `last_time` ) 0 `run: and last_time` )
            ( json_free upd )
        }
        F e → { ( check F `run: model change` ) ( string_free e ) }
    }
    ( json_free chm )
    : Json chb ( json_obj_new )
    ( json_obj_set chb `model` ( json_str_lit `fmi_test` ) )
    ?? ( source_update ORG ( string_data id ) chb + now 6 ) { T upd → { ( json_free upd ) } F e → { ( string_free e ) } }
    ( json_free chb )
    : b _d ( source_delete ORG ( string_data id ) )
    ( string_free id )
}

// ── wide ──────────────────────────────────────────────────────────────

@ test_wide Store st → v {
    ( check ( wfs_caps_has_stored CAPS_XML ) `wide: capabilities mention stored queries` )
    ( check ! ( wfs_caps_has_stored WIDE_XML ) `wide: a collection does not` )
    : Json cat ( wfs_catalog CAPS_XML )
    ( check ! ( jhas cat `error` ) `wide: capabilities parse as a catalogue` )
    ?? ( json_obj_get cat `queries` ) {
        T qs → {
            ( check == ( json_arr_len qs ) 2 `wide: two feature types` )
            ?? ( json_arr_get qs 0 ) {
                T q → {
                    ( check ( seq ( jstr q `id` ) `dwd:RBSN_T2m` ) `wide: type name is the id` )
                    ( check ( seq ( jstr q `kind` ) `type` ) `wide: kind type` )
                    ( check ( seq ( jstr q `title` ) `2m Temperatur an RBSN Stationen` ) `wide: type title` )
                }
                F _ → { ( check F `wide: type 0` ) }
            }
        }
        F _ → { ( check F `wide: queries` ) }
    }
    ( json_free cat )
    : Json scat ( wfs_catalog CATALOG_XML )
    ?? ( json_obj_get scat `queries` ) {
        T qs → { ?? ( json_arr_get qs 0 ) { T q → { ( check ( seq ( jstr q `kind` ) `stored` ) `wide: a stored query says so` ) } F _ → {} } }
        F _ → {}
    }
    ( json_free scat )

    : Json params ( json_obj_new )
    ( json_obj_set params `count` ( json_str_lit `250` ) )
    ( json_obj_set params `cql_filter` ( json_str_lit `TEMPERATURE > 10` ) )
    ( json_obj_set params `bbox` ( json_str_lit `` ) )
    : String tu ( wfs_url_type `https://maps.dwd.de/geoserver/dwd/ows?x=1` `dwd:RBSN_T2m` params )
    ( check ( string_contains tu `request=GetFeature&typeNames=dwd%3ARBSN_T2m` ) `wide: url names the type` )
    ( check ( string_contains tu `&cql_filter=TEMPERATURE%20%3E%2010` ) `wide: url passes a filter` )
    ( check ( string_contains tu `&count=250` ) `wide: url takes the count` )
    ( check ( string_contains tu `&srsName=urn%3Aogc%3Adef%3Acrs%3AEPSG%3A%3A4326` ) `wide: url asks for WGS 84, latitude first` )
    ( check ! ( string_contains tu `bbox=` ) `wide: an empty parameter is not sent` )
    ( string_free tu )
    ( json_free params )
    : Json none ( json_obj_new )
    : String tu2 ( wfs_url_type `https://x/wfs` `a:b` none )
    ( check ( string_contains tu2 `&count=1000&srsName=` ) `wide: default count` )
    ( string_free tu2 )
    ( json_free none )

    : WfsPivot pv ( wfs_pivot_wide WIDE_XML `` 5000 )
    ( check == ( string_len . pv err ) 0 `wide pivot: no error` )
    ( check == . pv members 3 `wide pivot: three features` )
    ( check == ( vec_len [Json] . pv rows ) 3 `wide pivot: three rows` )
    ( check ( has_col . pv columns `TEMPERATURE` ) `wide pivot: number column` )
    ( check ( has_col . pv columns `NAME` ) `wide pivot: text column` )
    ( check ( has_col . pv columns `gml_id` ) `wide pivot: identity column` )
    ( check ( has_col . pv columns `lat` ) `wide pivot: latitude from the geometry` )
    ?? ( vec_get [Json] . pv rows 0 ) {
        T r0 → {
            ( check == ( jint r0 `timestamp` ) T_0500 `wide pivot: clock from M_DATE` )
            ( check ( seq ( jstr r0 `time` ) `2026-09-07T05:00:00Z` ) `wide pivot: ISO time kept` )
            ( check ( seq ( jstr r0 `NAME` ) `Leuchtturm Alte Weser` ) `wide pivot: text value` )
            ( check ( seq ( jstr r0 `gml_id` ) `RBSN_T2m.102` ) `wide pivot: gml:id` )
            ( check == ( jint r0 `ID` ) 102 `wide pivot: a numeric text is a number` )
            ( check ! ( jhas r0 `lowerCorner` ) `wide pivot: boundedBy skipped` )
            ?? ( json_obj_get r0 `lat` ) { T lv → { ?? ( json_num_as_f lv ) { T x → { ( check & > x 53.86 < x 53.87 `wide pivot: lat value` ) } F _ → { ( check F `wide pivot: lat` ) } } } F _ → { ( check F `wide pivot: lat` ) } }
        }
        F _ → { ( check F `wide pivot: row 0` ) }
    }
    ?? ( vec_get [Json] . pv rows 1 ) {
        T r1 → {
            ( check ! ( jhas r1 `TEMPERATURE` ) `wide pivot: NaN left out` )
            ( check == ( jint r1 `timestamp` ) T_0600 `wide pivot: second clock` )
        }
        F _ → { ( check F `wide pivot: row 1` ) }
    }
    ( wfs_pivot_free pv )
    : WfsPivot pz ( wfs_pivot_wide WIDE_XML `none` 5000 )
    ?? ( vec_get [Json] . pz rows 0 ) {
        T r0 → { ( check & == ( jint r0 `timestamp` ) 5000 ! ( jhas r0 `time` ) `wide pivot: "none" means no property is the clock` ) }
        F _ → { ( check F `wide pivot: none clock` ) }
    }
    ( wfs_pivot_free pz )
    : WfsPivot pn ( wfs_pivot_wide WIDE_XML `NAME` 5000 )
    ?? ( vec_get [Json] . pn rows 0 ) {
        T r0 → { ( check == ( jint r0 `timestamp` ) 5000 `wide pivot: a named clock that is no date falls back to now` ) }
        F _ → { ( check F `wide pivot: named clock` ) }
    }
    ( wfs_pivot_free pn )
    : WfsPivot ps ( wfs_pivot_wide SNAPSHOT_XML `` 7000 )
    ( check == ( vec_len [Json] . ps rows ) 1 `wide pivot: snapshot row` )
    ?? ( vec_get [Json] . ps rows 0 ) {
        T r0 → {
            ( check == ( jint r0 `timestamp` ) 7000 `wide pivot: no date → stamped now` )
            ( check ! ( jhas r0 `time` ) `wide pivot: no ISO time for a snapshot` )
            ( check == ( jint r0 `POPULATION` ) 2140526 `wide pivot: population` )
        }
        F _ → { ( check F `wide pivot: snapshot` ) }
    }
    ( wfs_pivot_free ps )
    : WfsPivot pe ( wfs_pivot_wide EXCEPTION_XML `` 1 )
    ( check ( string_contains . pe err `exception` ) `wide pivot: exception surfaces` )
    ( wfs_pivot_free pe )

    // A feature-type source: window, categorical coordinates, the span.
    : Json b ( json_obj_new )
    ( json_obj_set b `url` ( json_str_lit `https://maps.dwd.de/geoserver/dwd/ows` ) )
    ( json_obj_set b `query` ( json_str_lit `dwd:RBSN_T2m` ) )
    ( json_obj_set b `mode` ( json_str_lit `type` ) )
    ( json_obj_set b `model` ( json_str_lit `dwd_t2m` ) )
    : Json f ( json_arr_new )
    ( json_arr_push f ( json_str_lit `TEMPERATURE` ) ) ( json_arr_push f ( json_str_lit `lat` ) ) ( json_arr_push f ( json_str_lit `lon` ) ) ( json_arr_push f ( json_str_lit `NAME` ) )
    ( json_obj_set b `features` f )
    : Json c ( json_arr_new )
    ( json_arr_push c ( json_str_lit `lat` ) ) ( json_arr_push c ( json_str_lit `lon` ) )
    ( json_obj_set b `categorical` c )
    : ~ String id ( string_new )
    ?? ( source_create ORG b `tester` 1000 ) {
        T src → {
            ( string_free id ) = id ( string_from ( jstr src `id` ) )
            ( check ( seq ( jstr src `mode` ) `type` ) `type source: mode kept` )
            ( check ( source_is_type src ) `type source: is a type` )
            : SrcWindow w ( source_window src 9000 F 0 )
            ( check & == . w start - 9000 604800 == . w end 9000 `type source: first window reaches history_hours back and stops at the fetch time` )
            ( json_obj_set src `allow_future` ( json_bool T ) )
            : SrcWindow wf ( source_window src 9000 F 0 )
            ( check > . wf end + 9000 100000000 `type source: allow_future opens the end` )
            ( json_obj_set src `allow_future` ( json_bool F ) )
            : SrcWindow wb ( source_window src 9000 T 24 )
            ( check & == . wb start - 9000 86400 == . wb end 9000 `type source: a backfill reaches back from the fetch time` )
            ( json_free src )
        }
        F e → { ( check F `type source: create` ) ( string_free e ) }
    }
    ( json_free b )
    : Json bad ( json_obj_new )
    ( json_obj_set bad `mode` ( json_str_lit `sideways` ) )
    ?? ( source_update ORG ( string_data id ) bad 1100 ) {
        T src → { ( check F `type source: bad mode refused` ) ( json_free src ) }
        F e → { ( check ( string_contains e `mode must be` ) `type source: bad mode refused` ) ( string_free e ) }
    }
    ( json_free bad )

    : i now + T_0600 600
    : WfsPivot pw ( wfs_pivot_wide WIDE_XML `` now )
    : ( Vec Json ) rows ( vec_new [Json] )
    : i nr ( vec_len [Json] . pw rows )
    : ~ i k 0
    ~ < k nr { ?? ( vec_get [Json] . pw rows k ) { T r → { ( vec_push [Json] rows ( json_clone r ) ) } F _ → {} } = k + k 1 }
    ( wfs_pivot_free pw )
    : ~ Json cur ( json_null )
    ?? ( source_load ORG ( string_data id ) ) { T sj → { ( json_free cur ) = cur sj } F _ → {} }
    : SrcWindow w2 ( source_window cur now F 0 )
    ( json_free cur )
    : Json r1 ( source_run_rows ORG ( string_data id ) @ !( Vec Json ) String { T rows } w2 F now )
    ( check ( seq ( jstr r1 `status` ) `success` ) `type run: success` )
    ( check == ( jint r1 `ingested` ) 3 `type run: three features in` )
    ( json_free r1 )
    // The same features again: nothing new, and the span does not move.
    : WfsPivot pw2 ( wfs_pivot_wide WIDE_XML `` + now 100 )
    : ( Vec Json ) rows2 ( vec_new [Json] )
    : i nr2 ( vec_len [Json] . pw2 rows )
    = k 0
    ~ < k nr2 { ?? ( vec_get [Json] . pw2 rows k ) { T r → { ( vec_push [Json] rows2 ( json_clone r ) ) } F _ → {} } = k + k 1 }
    ( wfs_pivot_free pw2 )
    : ~ Json cur2 ( json_null )
    ?? ( source_load ORG ( string_data id ) ) { T sj → { ( json_free cur2 ) = cur2 sj } F _ → {} }
    : SrcWindow w4 ( source_window cur2 + now 100 F 0 )
    ( json_free cur2 )
    : Json r2 ( source_run_rows ORG ( string_data id ) @ !( Vec Json ) String { T rows2 } w4 F + now 100 )
    ( check == ( jint r2 `ingested` ) 0 `type run: the same features land once` )
    ( json_free r2 )
    ?? ( source_load ORG ( string_data id ) ) {
        T src → {
            ( check == ( jint src `last_time` ) T_0600 `type run: last_time is the newest feature's clock` )
            ( check == ( jint src `first_time` ) T_0500 `type run: first_time is the oldest` )
            : SrcWindow w3 ( source_window src + now 60 F 0 )
            ( check == . w3 start + T_0600 1 `type run: the next window starts after the newest clock` )
            ( json_free src )
        }
        F _ → { ( check F `type run: reload` ) }
    }
    : *Model mo ( model_open st `dwd_t2m` )
    ( check == ( model_n_points mo ) 3 `type run: model holds three points` )
    : Json mj ( meta_to_json . mo meta )
    ?? ( json_obj_get mj `column_types` ) {
        T ct → {
            ( check ( seq ( jstr ct `lat` ) `categorical` ) `type run: a categorical coordinate is a categorical column` )
            ( check ( seq ( jstr ct `TEMPERATURE` ) `numeric` ) `type run: the temperature stays numeric` )
            ( check ( seq ( jstr ct `NAME` ) `categorical` ) `type run: text is categorical` )
        }
        F _ → { ( check F `type run: column_types` ) }
    }
    ( json_free mj )
    ?? ( vec_get [String] . mo lines 0 ) {
        T line → {
            ( check ( string_contains line `"lat":"53.8633"` ) `type run: a categorical coordinate is stored as text` )
            ( check ( string_contains line `"TEMPERATURE":17.5` ) `type run: a number stays a number` )
            ( check ( string_contains line `"NAME":"Leuchtturm Alte Weser"` ) `type run: text feature kept` )
            ( check ! ( string_contains line `gml_id` ) `type run: identity not taken unasked` )
        }
        F _ → { ( check F `type run: stored line` ) }
    }
    ( model_free mo )
    : b _d ( source_delete ORG ( string_data id ) )
    ( string_free id )
}

// ── due ───────────────────────────────────────────────────────────────

@ test_due → v {
    : String id ( make_source )
    : ( Vec SrcRef ) d1 ( sources_due 5000 )
    ( check == ( vec_len [SrcRef] d1 ) 1 `due: a fresh source is due` )
    ?? ( vec_get [SrcRef] d1 0 ) {
        T r → { ( check & ( seq ( string_data . r org ) ORG ) ( seq ( string_data . r id ) ( string_data id ) ) `due: names org and id` ) }
        F _ → { ( check F `due: ref` ) }
    }
    ( vec_free_with [SrcRef] d1 \ SrcRef r → v { ( string_free . r org ) ( string_free . r id ) } )
    ?? ( source_load ORG ( string_data id ) ) {
        T src → {
            ( json_obj_set src `last_run` ( json_int 5000 ) )
            : b _s ( source_save ORG src )
            ( json_free src )
        }
        F _ → {}
    }
    : ( Vec SrcRef ) d2 ( sources_due + 5000 599 )
    ( check == ( vec_len [SrcRef] d2 ) 0 `due: not due before the interval passes` )
    ( vec_free_with [SrcRef] d2 \ SrcRef r → v { ( string_free . r org ) ( string_free . r id ) } )
    : ( Vec SrcRef ) d3 ( sources_due + 5000 600 )
    ( check == ( vec_len [SrcRef] d3 ) 1 `due: due when it has` )
    ( vec_free_with [SrcRef] d3 \ SrcRef r → v { ( string_free . r org ) ( string_free . r id ) } )
    : Json off ( json_obj_new )
    ( json_obj_set off `enabled` ( json_bool F ) )
    ?? ( source_update ORG ( string_data id ) off 6000 ) { T s → { ( json_free s ) } F e → { ( string_free e ) } }
    ( json_free off )
    : ( Vec SrcRef ) d4 ( sources_due 99999 )
    ( check == ( vec_len [SrcRef] d4 ) 0 `due: a disabled source never is` )
    ( vec_free_with [SrcRef] d4 \ SrcRef r → v { ( string_free . r org ) ( string_free . r id ) } )
    ( check == ( sources_tick 99999 \ → v { ( nop ) } \ → v { ( nop ) } ) 0 `due: a tick with nothing due runs nothing` )
    : b _d ( source_delete ORG ( string_data id ) )
    ( string_free id )
}

// ── routes ────────────────────────────────────────────────────────────

@ mk_req s method s path s query s body → HttpRequest {
    ^ @ HttpRequest {
        ( string_from method )
        ( string_from path )
        ( string_from query )
        ( string_from `HTTP/1.1` )
        ( vec_new [Header] )
        ( bytes_from_str body )
    }
}

: SvcOut {
    i status
    Json body
}

@ fire Router r s method s path s query s body → SvcOut {
    : HttpRequest req ( mk_req method path query body )
    : HttpResponse resp ( router_handle r req )
    : i status . resp status
    : String txt ( bytes_to_str . resp body )
    : ~ Json parsed ( json_null )
    : !Json JsonError jr ( json_parse ( string_data txt ) )
    ?? jr {
        T j → { ( json_free parsed ) = parsed j }
        F _ → {}
    }
    ( string_free txt )
    ( http_response_free resp )
    ( request_free req )
    ^ @ SvcOut { status parsed }
}

// ── http ──────────────────────────────────────────────────────────────

@ test_http Router r → v {
    : WfsPivot pa ( http_pivot JSON_ARRAY `data.items` `` 5000 )
    ( check == ( string_len . pa err ) 0 `http pivot: array parses` )
    ( check == ( vec_len [Json] . pa rows ) 3 `http pivot: three records` )
    ( check ( has_col . pa columns `reading_temperature` ) `http pivot: nested keys flattened` )
    ( check ( has_col . pa columns `ok` ) `http pivot: booleans are columns` )
    ( check ! ( has_col . pa columns `tags` ) `http pivot: arrays left out` )
    ( check ! ( has_col . pa columns `note` ) `http pivot: nulls left out` )
    ?? ( vec_get [Json] . pa rows 0 ) {
        T r0 → {
            ( check == ( jint r0 `timestamp` ) T_0500 `http pivot: clock detected from "measured"` )
            ( check ( seq ( jstr r0 `name` ) `Kumpula` ) `http pivot: text kept` )
            ( check == ( jint r0 `ok` ) 1 `http pivot: true is 1` )
            ( check == ( jint r0 `reading_humidity` ) 82 `http pivot: nested number` )
        }
        F _ → { ( check F `http pivot: row 0` ) }
    }
    ?? ( vec_get [Json] . pa rows 2 ) {
        T r2 → { ( check ( seq ( jstr r2 `reading_temperature` ) `NaN` ) `http pivot: a "NaN" string stays text (the column table will say mixed)` ) }
        F _ → { ( check F `http pivot: row 2` ) }
    }
    ( wfs_pivot_free pa )
    : WfsPivot po ( http_pivot JSON_OBJECT `current` `` 7000 )
    ( check == ( vec_len [Json] . po rows ) 1 `http pivot: an object is one record` )
    ?? ( vec_get [Json] . po rows 0 ) {
        T r0 → {
            ( check ( jhas r0 `timestamp` ) `http pivot: naive time read` )
            ( check ( seq ( jstr r0 `time` ) `2026-09-07T13:15:00Z` ) `http pivot: naive time taken as UTC` )
            ( check == ( jint r0 `wind_speed_10m` ) 9 `http pivot: value` )
        }
        F _ → { ( check F `http pivot: object row` ) }
    }
    ( wfs_pivot_free po )
    : WfsPivot pw ( http_pivot JSON_OBJECT `` `none` 7000 )
    ?? ( vec_get [Json] . pw rows 0 ) {
        T r0 → { ( check & ( jhas r0 `current_temperature_2m` ) == ( jint r0 `timestamp` ) 7000 `http pivot: whole answer flattened, no clock → now` ) }
        F _ → { ( check F `http pivot: whole` ) }
    }
    ( wfs_pivot_free pw )
    : WfsPivot pm ( http_pivot JSON_OBJECT `nowhere.here` `` 1 )
    ( check ( string_contains . pm err `nothing at the path` ) `http pivot: a missing path says so` )
    ( wfs_pivot_free pm )
    : WfsPivot pj ( http_pivot `<html>` `` `` 1 )
    ( check ( string_contains . pj err `not JSON` ) `http pivot: HTML is not JSON` )
    ( wfs_pivot_free pj )

    // A source: created with headers, listed masked, edited with the mask.
    : SvcOut c1 ( fire r `POST` `/api/org/sources` `` `{"kind":"http","url":"http://127.0.0.1:9/api/v1/readings?station=1","method":"GET","headers":{"Digitraffic-User":"anomaly-test","Authorization":"Bearer s3cret"},"path":"data.items","features":["reading_temperature","name"],"categorical":["name"],"model":"http_test"}` )
    ( check == . c1 status 201 `http source: created` )
    : String id ( string_from ( jstr . c1 body `id` ) )
    ( check ( seq ( jstr . c1 body `kind` ) `http` ) `http source: kind kept` )
    ( check ( seq ( jstr . c1 body `name` ) `http://127.0.0.1:9/api/v1/readings?station=1` ) `http source: named after the url` )
    ?? ( json_obj_get . c1 body `headers` ) {
        T h → {
            ( check ( seq ( jstr h `Authorization` ) `••••••••` ) `http source: a credential header is masked in the answer` )
            ( check ( seq ( jstr h `Digitraffic-User` ) `anomaly-test` ) `http source: a header that only names the caller is shown` )
        }
        F _ → { ( check F `http source: headers` ) }
    }
    ( json_free . c1 body )
    ?? ( source_load ORG ( string_data id ) ) {
        T src → {
            ?? ( json_obj_get src `headers` ) {
                T h → { ( check ( seq ( jstr h `Authorization` ) `Bearer s3cret` ) `http source: the stored value is the real one` ) }
                F _ → { ( check F `http source: stored headers` ) }
            }
            ( check ( source_is_type src ) `http source: fetched whole each run` )
            ( json_free src )
        }
        F _ → { ( check F `http source: load` ) }
    }
    : String path ( string_from `/api/org/sources/` )
    ( string_push_str path ( string_data id ) )
    : SvcOut u1 ( fire r `PUT` ( string_data path ) `` `{"headers":{"Digitraffic-User":"renamed","Authorization":"••••••••"},"path":"data.items"}` )
    ( check == . u1 status 200 `http source: edited` )
    ( json_free . u1 body )
    ?? ( source_load ORG ( string_data id ) ) {
        T src → {
            ?? ( json_obj_get src `headers` ) {
                T h → {
                    ( check ( seq ( jstr h `Authorization` ) `Bearer s3cret` ) `http source: the mask sent back keeps the stored value` )
                    ( check ( seq ( jstr h `Digitraffic-User` ) `renamed` ) `http source: a new value replaces` )
                }
                F _ → { ( check F `http source: edited headers` ) }
            }
            ( json_free src )
        }
        F _ → { ( check F `http source: reload` ) }
    }
    : SvcOut u2 ( fire r `PUT` ( string_data path ) `` `{"headers":{"Bad Name":"x"}}` )
    ( check == . u2 status 400 `http source: a header name with a space is refused` )
    ( json_free . u2 body )
    : SvcOut u3 ( fire r `PUT` ( string_data path ) `` `{"method":"DELETE"}` )
    ( check == . u3 status 400 `http source: DELETE is not a poll` )
    ( json_free . u3 body )
    : SvcOut c2 ( fire r `POST` `/api/org/sources` `` `{"kind":"http","url":"https://example.org/x","model":"m"}` )
    ( check == . c2 status 201 `http source: no query needed` )
    : String id2 ( string_from ( jstr . c2 body `id` ) )
    ( json_free . c2 body )
    : b _d2 ( source_delete ORG ( string_data id2 ) )
    ( string_free id2 )
    : SvcOut c3 ( fire r `POST` `/api/org/sources` `` `{"kind":"ftp","url":"https://example.org/x","model":"m"}` )
    ( check == . c3 status 400 `http source: an unknown kind is refused` )
    ( json_free . c3 body )

    // A run against a closed port: the failure on the record.
    : String rpath ( string_clone path )
    ( string_push_str rpath `/run` )
    : SvcOut r1 ( fire r `POST` ( string_data rpath ) `` `` )
    ( check == . r1 status 400 `http source: an unreachable url fails the run` )
    ( check ( has_text ( jstr . r1 body `message` ) `could not fetch` ) `http source: and says why` )
    ( json_free . r1 body )
    ( string_free rpath )
    : SvcOut p1 ( fire r `POST` `/api/org/sources/preview` `` `{"kind":"http","url":"http://127.0.0.1:9/x","path":"","headers":{"X-Key":"k"}}` )
    ( check == . p1 status 502 `http source: an unreachable preview is 502` )
    ( json_free . p1 body )

    : SvcOut d1 ( fire r `DELETE` ( string_data path ) `` `` )
    ( check == . d1 status 200 `http source: deleted` )
    ( json_free . d1 body )
    ( string_free path )
    ( string_free id )
}

@ test_routes → v {
    : Router r ( anomaly_service_router )

    : SvcOut l0 ( fire r `GET` `/api/org/sources` `` `` )
    ( check == . l0 status 200 `routes: GET /api/org/sources 200` )
    ?? ( json_obj_get . l0 body `sources` ) {
        T arr → { ( check == ( json_arr_len arr ) 0 `routes: none yet` ) }
        F _ → { ( check F `routes: sources array` ) }
    }
    ( json_free . l0 body )

    : SvcOut c0 ( fire r `POST` `/api/org/sources` `` `{"url":"ftp://x"}` )
    ( check == . c0 status 400 `routes: a bad body is 400` )
    ( json_free . c0 body )
    : SvcOut c1 ( fire r `POST` `/api/org/sources` `` `not json` )
    ( check == . c1 status 400 `routes: not JSON is 400` )
    ( json_free . c1 body )

    : Json b ( body_full )
    ( json_obj_set b `name` ( json_str_lit `Helsinki` ) )
    : String bs ( json_stringify b )
    ( json_free b )
    : SvcOut c2 ( fire r `POST` `/api/org/sources` `` ( string_data bs ) )
    ( string_free bs )
    ( check == . c2 status 201 `routes: created 201` )
    : String id ( string_from ( jstr . c2 body `id` ) )
    ( check ( source_id_ok ( string_data id ) ) `routes: the answer carries the id` )
    ( check ( seq ( jstr . c2 body `name` ) `Helsinki` ) `routes: and the record` )
    ( check ( jhas . c2 body `running` ) `routes: and whether it runs` )
    ( json_free . c2 body )

    : String path ( string_from `/api/org/sources/` )
    ( string_push_str path ( string_data id ) )
    : SvcOut g1 ( fire r `GET` ( string_data path ) `` `` )
    ( check == . g1 status 200 `routes: GET one 200` )
    ( check ( seq ( jstr . g1 body `model` ) `helsinki_weather` ) `routes: GET one has the model` )
    ( json_free . g1 body )
    : SvcOut g2 ( fire r `GET` `/api/org/sources/000000000000` `` `` )
    ( check == . g2 status 404 `routes: unknown id 404` )
    ( json_free . g2 body )
    : SvcOut g3 ( fire r `GET` `/api/org/sources/not-an-id` `` `` )
    ( check == . g3 status 400 `routes: malformed id 400` )
    ( json_free . g3 body )

    : SvcOut u1 ( fire r `PUT` ( string_data path ) `` `{"interval_minutes": 5, "enabled": false}` )
    ( check == . u1 status 200 `routes: PUT 200` )
    ( check == ( jint . u1 body `interval_minutes` ) 5 `routes: PUT changed the interval` )
    ( json_free . u1 body )
    : SvcOut u2 ( fire r `PUT` ( string_data path ) `` `{"interval_minutes": 0}` )
    ( check == . u2 status 400 `routes: PUT with a bad value 400` )
    ( json_free . u2 body )

    : SvcOut l1 ( fire r `GET` `/api/org/sources` `` `` )
    ?? ( json_obj_get . l1 body `sources` ) {
        T arr → { ( check == ( json_arr_len arr ) 1 `routes: one listed` ) }
        F _ → { ( check F `routes: sources array` ) }
    }
    ( json_free . l1 body )

    // Run: the URL is a real host nobody listens on, so the run fails
    // fast and the failure is the answer.
    : SvcOut u3 ( fire r `PUT` ( string_data path ) `` `{"url": "http://127.0.0.1:9/wfs"}` )
    ( check == . u3 status 200 `routes: PUT url` )
    ( json_free . u3 body )
    : String rpath ( string_clone path )
    ( string_push_str rpath `/run` )
    : SvcOut r1 ( fire r `POST` ( string_data rpath ) `` `` )
    ( check == . r1 status 400 `routes: a failed run is 400` )
    ( check ( seq ( jstr . r1 body `status` ) `error` ) `routes: with status error` )
    ( json_free . r1 body )
    : SvcOut r2 ( fire r `POST` `/api/org/sources/000000000000/run` `` `` )
    ( check == . r2 status 404 `routes: running an unknown source 404` )
    ( json_free . r2 body )
    ( string_free rpath )

    : SvcOut k1 ( fire r `POST` `/api/org/sources/catalog` `` `{"url": "ftp://nope"}` )
    ( check == . k1 status 400 `routes: catalogue needs an http(s) url` )
    ( json_free . k1 body )
    : SvcOut k2 ( fire r `POST` `/api/org/sources/catalog` `` `{"url": "http://127.0.0.1:9/wfs"}` )
    ( check == . k2 status 502 `routes: an unreachable catalogue is 502` )
    ( json_free . k2 body )
    : SvcOut p1 ( fire r `POST` `/api/org/sources/preview` `` `{"url": "https://opendata.fmi.fi/wfs"}` )
    ( check == . p1 status 400 `routes: preview needs a query` )
    ( json_free . p1 body )
    : SvcOut p2 ( fire r `POST` `/api/org/sources/preview` `` `{"url": "http://127.0.0.1:9/wfs", "query": "x::simple", "hours": 1}` )
    ( check == . p2 status 502 `routes: an unreachable preview is 502` )
    ( json_free . p2 body )

    : SvcOut d1 ( fire r `DELETE` ( string_data path ) `` `` )
    ( check == . d1 status 200 `routes: DELETE 200` )
    ( json_free . d1 body )
    : SvcOut d2 ( fire r `DELETE` ( string_data path ) `` `` )
    ( check == . d2 status 404 `routes: DELETE twice 404` )
    ( json_free . d2 body )
    ( string_free path )
    ( string_free id )
    ( router_free r )
}

// `string_contains` takes a String, and a String built inline is never
// freed. One helper, so a test does not leak per assertion.
@ has_text s hay s needle → b {
    ^ >= ( nurl_str_find hay needle ) 0
}

@ starts_text s hay s pre → b {
    : i hn ( nurl_str_len hay )
    : i pn ( nurl_str_len pre )
    ? > pn hn { ^ F } {}
    : ~ i k 0
    ~ < k pn {
        ? == ( nurl_str_at hay hn k ) ( nurl_str_at pre pn k ) {} { ^ F }
        = k + k 1
    }
    ^ T
}

@ main → i {
    : String root ( env_var_or `ANOMALY_TEST_DIR` `./anomaly_sources_test` )
    : !v IoErr junk ( dir_remove_all ( string_data root ) )
    ?? junk { T _ → {} F _ → {} }
    ( anomaly_service_set_root ( string_data root ) )
    ( anomaly_authz_set_root ( string_data root ) )
    : Store st ( store_open ( string_data root ) )

    ( test_wfs )
    ( test_sources )
    ( test_windows )
    ( test_autotune st )
    ( test_run st )
    ( test_wide st )
    : Router rh ( anomaly_service_router )
    ( test_http rh )
    ( router_free rh )
    ( test_due )
    ( test_routes )

    ( store_free st )
    : !v IoErr fin ( dir_remove_all ( string_data root ) )
    ?? fin { T _ → {} F _ → {} }
    ( string_free root )
    ( nurl_print `sources_test: ` ) ( nurl_print_int g_pass )
    ( nurl_print ` passed, ` ) ( nurl_print_int g_fail ) ( nurl_print ` failed\n` )
    ^ ? > g_fail 0 1 0
}
