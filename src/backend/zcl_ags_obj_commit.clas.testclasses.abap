
CLASS ltcl_test DEFINITION FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS
  FINAL.

  PRIVATE SECTION.
    CONSTANTS: c_sha1 TYPE zags_sha1 VALUE '5f46cb3c4b7f0b3600b64f744cde614a283a88dc'.

    METHODS:
      serialize FOR TESTING
        RAISING zcx_ags_error.

ENDCLASS.       "ltcl_Test


CLASS ltcl_test IMPLEMENTATION.

  METHOD serialize.

    DATA: lo_old  TYPE REF TO zcl_ags_obj_commit,
          lo_new  TYPE REF TO zcl_ags_obj_commit,
          lv_xstr TYPE xstring.


    CREATE OBJECT lo_old.
    lo_old->set_author( 'author' ).
    lo_old->set_body( 'body' ).
    lo_old->set_committer( 'committer' ).
    lo_old->set_parent( c_sha1 ).
    lo_old->set_tree( c_sha1 ).
    lv_xstr = lo_old->zif_ags_object~serialize( ).

    CREATE OBJECT lo_new.
    lo_new->zif_ags_object~deserialize( lv_xstr ).

    cl_abap_unit_assert=>assert_equals(
        act = lo_new->get( )-author
        exp = lo_old->get( )-author ).

    cl_abap_unit_assert=>assert_equals(
        act = lo_new->get( )-body
        exp = lo_old->get( )-body ).

    cl_abap_unit_assert=>assert_equals(
        act = lo_new->get( )-committer
        exp = lo_old->get( )-committer ).

    cl_abap_unit_assert=>assert_equals(
        act = lo_new->get( )-parent
        exp = lo_old->get( )-parent ).

    cl_abap_unit_assert=>assert_equals(
        act = lo_new->get( )-tree
        exp = lo_old->get( )-tree ).

  ENDMETHOD.

ENDCLASS.