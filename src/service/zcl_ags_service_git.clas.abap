CLASS zcl_ags_service_git DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.

    INTERFACES zif_ags_service.

    METHODS constructor
      IMPORTING
        !ii_server TYPE REF TO if_http_server.
  PROTECTED SECTION.
  PRIVATE SECTION.

    TYPES:
      BEGIN OF ty_push,
        old    TYPE zags_sha1,
        new    TYPE zags_sha1,
        name   TYPE zags_branch_name,
        length TYPE i,
      END OF ty_push.

    DATA mi_server TYPE REF TO if_http_server.

    METHODS branch_list
      RAISING
        zcx_ags_error.
    METHODS decode_push
      IMPORTING
        !iv_data       TYPE xstring
      RETURNING
        VALUE(rs_push) TYPE ty_push
      RAISING
        zcx_ags_error.
    METHODS decode_want
      IMPORTING
        !iv_string     TYPE string
      RETURNING
        VALUE(rv_sha1) TYPE zags_sha1.
    METHODS get_null
      RETURNING
        VALUE(rv_char) TYPE char1.
    METHODS pack
      RAISING
        zcx_ags_error.
    METHODS repo_name
      RETURNING
        VALUE(rv_name) TYPE zags_repos-name.
    METHODS unpack
      RAISING
        zcx_ags_error.
    METHODS unpack_ok.
ENDCLASS.



CLASS ZCL_AGS_SERVICE_GIT IMPLEMENTATION.


  METHOD branch_list.

    DEFINE _capability.
      APPEND &1 TO lt_capabilities ##NO_TEXT.
    END-OF-DEFINITION.

    DATA: lv_reply        TYPE string,
          lt_reply        TYPE TABLE OF string,
          lv_length       TYPE xstring,
          lt_capabilities TYPE TABLE OF string.


    _capability 'multi_ack'.
    _capability 'thin-pack'.
    _capability 'side-band'.
    _capability 'side-band-64k'.
    _capability 'ofs-delta'.
    _capability 'shallow'.
    _capability 'no-progress'.
    _capability 'include-tag'.
    _capability 'multi_ack_detailed'.
    _capability 'no-done'.
    _capability 'symref=HEAD:refs/heads/master'.
    _capability 'agent=git/abapGitServer'.

    CONCATENATE LINES OF lt_capabilities INTO lv_reply SEPARATED BY space.

    DATA(lv_name) = repo_name( ).
    DATA(lo_repo) = NEW zcl_ags_repo( lv_name ).
    DATA(lv_head) = lo_repo->get_branch( lo_repo->get_data( )-head )->get_data( )-sha1.

    APPEND '001e# service=git-upload-pack' TO lt_reply ##NO_TEXT.
    APPEND '000000e8' && lv_head && ' HEAD' && get_null( ) && lv_reply TO lt_reply.

    LOOP AT lo_repo->list_branches( ) ASSIGNING FIELD-SYMBOL(<lo_branch>).
      DATA(lv_content) = <lo_branch>->get_data( )-sha1
        && ' refs/heads/'
        && <lo_branch>->get_data( )-name ##NO_TEXT.
      lv_length = lcl_length=>encode( strlen( lv_content ) + 4 ).
      DATA(lv_utf) = zcl_ags_util=>xstring_to_string_utf8( lv_length ).
      APPEND lv_utf && lv_content TO lt_reply.
    ENDLOOP.

    APPEND '0000' TO lt_reply.

    CONCATENATE LINES OF lt_reply INTO lv_reply
      SEPARATED BY cl_abap_char_utilities=>newline.

    mi_server->response->set_cdata( lv_reply ).

  ENDMETHOD.


  METHOD constructor.

    mi_server = ii_server.

  ENDMETHOD.


  METHOD decode_push.

    DATA: lt_data TYPE TABLE OF string.

    DATA(lv_first) = iv_data(4).
    DATA(lv_utf) = zcl_ags_util=>xstring_to_string_utf8( lv_first ).
    rs_push-length = lcl_length=>decode( lv_utf ).

    lv_first = iv_data(rs_push-length).
    DATA(lv_data) = zcl_ags_util=>xstring_to_string_utf8( lv_first ).
    lv_data = lv_data+4. " skip length, already decoded

    SPLIT lv_data AT get_null( ) INTO TABLE lt_data.
    ASSERT lines( lt_data ) > 0.

    lv_data = lt_data[ 1 ].

    rs_push-old  = lv_data.
    rs_push-new  = lv_data+41.
    rs_push-name = lv_data+93. " also skip 'refs/heads/'

  ENDMETHOD.


  METHOD decode_want.

* todo, proper decoding
    rv_sha1 = iv_string+9.

  ENDMETHOD.


  METHOD get_null.

    DATA: lv_x(4) TYPE x VALUE '00000000',
          lv_z(2) TYPE c.

    FIELD-SYMBOLS <lv_y> TYPE c.


    ASSIGN lv_x TO <lv_y> CASTING.
    lv_z = <lv_y>.
    rv_char = lv_z(1).

  ENDMETHOD.


  METHOD pack.

    CONSTANTS: lc_band1 TYPE x VALUE '01'.

    DATA: lv_response TYPE xstring,
          lv_length   TYPE i.


    DATA(lv_branch) = decode_want( mi_server->request->get_cdata( ) ).

    DATA(lo_commit) = NEW zcl_ags_obj_commit( lv_branch ).

    DATA(lv_pack) = zcl_ags_pack=>encode( zcl_ags_pack=>explode( lo_commit ) ).

    WHILE xstrlen( lv_pack ) > 0.
      IF xstrlen( lv_pack ) >= 8196.
        lv_length = 8196.
      ELSE.
        lv_length = xstrlen( lv_pack ).
      ENDIF.

* make sure to include the length encoding itself and band identifier in the length
      DATA(lv_encoded) = lcl_length=>encode( lv_length + 5 ).

      CONCATENATE lv_response lv_encoded lc_band1 lv_pack(lv_length)
        INTO lv_response IN BYTE MODE.

      lv_pack = lv_pack+lv_length.
    ENDWHILE.

    mi_server->response->set_data( lv_response ).

  ENDMETHOD.


  METHOD repo_name.

    DATA(lv_path) = mi_server->request->get_header_field( '~path' ).
    FIND REGEX 'sap/zgit/git/(.*)\.git*'
      IN lv_path
      SUBMATCHES rv_name ##NO_TEXT.

  ENDMETHOD.


  METHOD unpack.

    CONSTANTS: lc_utf_0000 TYPE x LENGTH 4 VALUE '30303030'.


    DATA(ls_push) = decode_push( mi_server->request->get_data( ) ).

    DATA(lv_xstring) = mi_server->request->get_data( ).
    lv_xstring = lv_xstring+ls_push-length.
    ASSERT lv_xstring(4) = lc_utf_0000.
    lv_xstring = lv_xstring+4.

    DATA(lt_objects) = zcl_ags_pack=>decode( lv_xstring ).

    DATA(lo_repo) = NEW zcl_ags_repo( repo_name( ) ).

    IF ls_push-old CO '0'.
* create branch
      zcl_ags_branch=>create(
        io_repo   = lo_repo
        iv_name   = ls_push-name
        iv_commit = ls_push-new ).
    ELSEIF ls_push-new CO '0'.
* delete branch
* todo
      ASSERT 0 = 1.
    ELSE.
* update branch

      READ TABLE lt_objects WITH KEY sha1 = ls_push-new TRANSPORTING NO FIELDS.
* new commit should exist in objects
      ASSERT sy-subrc = 0.

      DATA(lo_branch) = lo_repo->get_branch( ls_push-name ).

      ASSERT lo_branch->get_data( )-sha1 = ls_push-old.

      zcl_ags_pack=>save( lt_objects ).

      lo_branch->update_sha1( ls_push-new ).
    ENDIF.

    unpack_ok( ).

  ENDMETHOD.


  METHOD unpack_ok.

* todo, this is all wrong(but will work in most cases):
    mi_server->response->set_cdata( '000eunpack ok#0019ok refs/heads/master#00000000' ).

  ENDMETHOD.


  METHOD zif_ags_service~run.

    DATA(lv_path) = mi_server->request->get_header_field( '~path_info' ).

    DATA(lv_xdata) = mi_server->request->get_data( ).

    IF lv_xdata IS INITIAL.
      branch_list( ).
    ELSEIF lv_path CP '*git-upload-pack*'.
      pack( ).
    ELSEIF lv_path CP '*git-receive-pack*'.
      unpack( ).
    ELSE.
      RAISE EXCEPTION TYPE zcx_ags_error
        EXPORTING
          textid = zcx_ags_error=>m008.
    ENDIF.

  ENDMETHOD.
ENDCLASS.