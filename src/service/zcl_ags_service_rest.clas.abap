CLASS zcl_ags_service_rest DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.

    INTERFACES zif_ags_service.
    INTERFACES zif_swag_handler.

    TYPES:
      BEGIN OF ty_create,
        name        TYPE zags_repos-name,
        description TYPE zags_repos-description,
      END OF ty_create.
    TYPES:
      BEGIN OF ty_branch,
        name   TYPE zags_branch_name,
        time   TYPE zags_unix_time,
        commit TYPE zags_sha1,
        head   TYPE abap_bool,
      END OF ty_branch.
    TYPES:
      BEGIN OF ty_file,
        filename    TYPE string,
        sha1        TYPE zags_sha1,
        comment     TYPE string,
        commit_sha1 TYPE zags_sha1,
        time        TYPE zags_unix_time,
      END OF ty_file.
    TYPES:
      ty_branches_tt TYPE STANDARD TABLE OF ty_branch WITH DEFAULT KEY.
    TYPES:
      ty_files_tt TYPE STANDARD TABLE OF ty_file WITH DEFAULT KEY.

    METHODS constructor
      IMPORTING
        !ii_server TYPE REF TO if_http_server.
    METHODS create_repo
      IMPORTING
        !is_data TYPE ty_create
      RAISING
        zcx_ags_error.
    METHODS list_branches
      IMPORTING
        !iv_repo           TYPE zags_repo_name
      RETURNING
        VALUE(rt_branches) TYPE ty_branches_tt
      RAISING
        zcx_ags_error.
    METHODS list_commits
      IMPORTING
        !iv_repo          TYPE zags_repo_name
        !iv_branch        TYPE zags_branch_name
      RETURNING
        VALUE(rt_commits) TYPE zcl_ags_obj_commit=>ty_pretty_tt
      RAISING
        zcx_ags_error.
    METHODS list_repos
      RETURNING
        VALUE(rt_list) TYPE zcl_ags_repo=>ty_repos_tt
      RAISING
        zcx_ags_error.
    METHODS list_files
      IMPORTING
        !iv_repo        TYPE zags_repo_name
        !iv_branch      TYPE zags_branch_name
      RETURNING
        VALUE(rt_files) TYPE ty_files_tt
      RAISING
        zcx_ags_error.
    METHODS read_blob
      IMPORTING
        !iv_repo           TYPE zags_repo_name
        !iv_branch         TYPE string
        !iv_filename       TYPE string
      RETURNING
        VALUE(rv_contents) TYPE xstring
      RAISING
        zcx_ags_error.
    METHODS read_commit
      IMPORTING
        !iv_commit     TYPE zags_sha1
      RETURNING
        VALUE(rs_data) TYPE zcl_ags_obj_commit=>ty_pretty
      RAISING
        zcx_ags_error.
  PROTECTED SECTION.
  PRIVATE SECTION.

    DATA mi_server TYPE REF TO if_http_server.
    CONSTANTS c_base TYPE string VALUE '/sap/zgit/rest' ##NO_TEXT.

    METHODS list_files_commit
      IMPORTING
        !iv_commit      TYPE zags_sha1
      RETURNING
        VALUE(rt_files) TYPE ty_files_tt
      RAISING
        zcx_ags_error.
ENDCLASS.



CLASS ZCL_AGS_SERVICE_REST IMPLEMENTATION.


  METHOD constructor.

    mi_server = ii_server.

  ENDMETHOD.


  METHOD create_repo.

    zcl_ags_repo=>create(
      iv_name        = is_data-name
      iv_description = is_data-description ).

  ENDMETHOD.


  METHOD list_branches.

    DATA(lo_repo) = NEW zcl_ags_repo( iv_repo ).
    DATA(lv_head) = lo_repo->get_data( )-head.
    DATA(lt_branches) = lo_repo->list_branches( ).

    LOOP AT lt_branches ASSIGNING FIELD-SYMBOL(<lo_branch>).
      APPEND INITIAL LINE TO rt_branches ASSIGNING FIELD-SYMBOL(<ls_output>).
      <ls_output>-name = <lo_branch>->get_data( )-name.

      DATA(lo_commit) = NEW zcl_ags_obj_commit( <lo_branch>->get_data( )-sha1 ).
      <ls_output>-time = lo_commit->get_pretty( )-committer-time.
      <ls_output>-commit = lo_commit->sha1( ).
      IF <ls_output>-name = lv_head.
        <ls_output>-head = abap_true.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.


  METHOD list_commits.

    DATA(lo_repo) = NEW zcl_ags_repo( iv_repo ).
    DATA(lo_branch) = lo_repo->get_branch( iv_branch ).
    DATA(lo_commit) = NEW zcl_ags_obj_commit( lo_branch->get_data( )-sha1 ).

    APPEND lo_commit->get_pretty( ) TO rt_commits.
    WHILE NOT lo_commit->get( )-parent IS INITIAL.
      lo_commit = NEW zcl_ags_obj_commit( lo_commit->get( )-parent ).
      APPEND lo_commit->get_pretty( ) TO rt_commits.
    ENDWHILE.

  ENDMETHOD.


  METHOD list_files.

    DATA(lo_repo) = NEW zcl_ags_repo( iv_repo ).
    DATA(lv_commit) = lo_repo->get_branch( iv_branch )->get_data( )-sha1.

    rt_files = list_files_commit( lv_commit ).

  ENDMETHOD.


  METHOD list_files_commit.

    TYPES: BEGIN OF ty_tree,
             sha1 TYPE zags_sha1,
             base TYPE string,
           END OF ty_tree.

    DATA: lt_trees TYPE STANDARD TABLE OF ty_tree WITH DEFAULT KEY.


    DATA(lo_commit) = NEW zcl_ags_obj_commit( iv_commit ).
    APPEND VALUE #( sha1 = lo_commit->get( )-tree base = '/' ) TO lt_trees.

    LOOP AT lt_trees ASSIGNING FIELD-SYMBOL(<ls_tree>).
      DATA(lo_tree) = NEW zcl_ags_obj_tree( <ls_tree>-sha1 ).
      DATA(lt_files) = lo_tree->get_files( ).
      LOOP AT lt_files ASSIGNING FIELD-SYMBOL(<ls_file>).
        CASE <ls_file>-chmod.
          WHEN zcl_ags_obj_tree=>c_chmod-dir.
            APPEND VALUE #(
              sha1 = <ls_file>-sha1
              base = <ls_tree>-base && <ls_file>-name && '/' )
              TO lt_trees.
          WHEN OTHERS.
            APPEND VALUE #(
              filename = <ls_tree>-base && <ls_file>-name
              sha1 = <ls_file>-sha1 )
              TO rt_files.
        ENDCASE.
      ENDLOOP.
    ENDLOOP.

* todo, at some point in time this recursion will break
* due to the number of commits
    IF NOT lo_commit->get( )-parent IS INITIAL.
      DATA(lt_old) = list_files_commit( lo_commit->get( )-parent ).
      LOOP AT rt_files ASSIGNING FIELD-SYMBOL(<ls_output>).
        READ TABLE lt_old ASSIGNING FIELD-SYMBOL(<ls_old>)
          WITH KEY filename = <ls_output>-filename.
        IF sy-subrc <> 0
            OR <ls_old>-sha1 <> <ls_output>-sha1.
          <ls_output>-comment     = lo_commit->get_pretty( )-text.
          <ls_output>-commit_sha1 = lo_commit->sha1( ).
          <ls_output>-time        = lo_commit->get_pretty( )-committer-time.
        ELSE.
          <ls_output>-comment     = <ls_old>-comment.
          <ls_output>-commit_sha1 = <ls_old>-commit_sha1.
          <ls_output>-time        = <ls_old>-time.
        ENDIF.
      ENDLOOP.
    ELSE.
      LOOP AT rt_files ASSIGNING <ls_output>.
        <ls_output>-comment     = lo_commit->get_pretty( )-text.
        <ls_output>-commit_sha1 = lo_commit->sha1( ).
        <ls_output>-time        = lo_commit->get_pretty( )-committer-time.
      ENDLOOP.
    ENDIF.

  ENDMETHOD.


  METHOD list_repos.

    rt_list = zcl_ags_repo=>list( ).

  ENDMETHOD.


  METHOD read_blob.

    DATA(lo_repo) = NEW zcl_ags_repo( iv_repo ).
    DATA(lv_commit) = lo_repo->get_branch( CONV #( iv_branch ) )->get_data( )-sha1.
    DATA(lt_files) = list_files_commit( lv_commit ).

    READ TABLE lt_files ASSIGNING FIELD-SYMBOL(<ls_file>)
      WITH KEY filename = '/' && iv_filename.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_ags_error
        EXPORTING
          textid = zcx_ags_error=>m011.
    ENDIF.

    DATA(lo_blob) = NEW zcl_ags_obj_blob( <ls_file>-sha1 ).
    rv_contents = lo_blob->get_data( ).

  ENDMETHOD.


  METHOD read_commit.

    DATA(lo_commit) = NEW zcl_ags_obj_commit( iv_commit ).
    rs_data = lo_commit->get_pretty( ).

  ENDMETHOD.


  METHOD zif_ags_service~run.

    DATA: lv_path TYPE string.


    DATA(lo_swag) = NEW zcl_swag(
      ii_server = mi_server
      iv_base   = c_base ).
    lo_swag->register( me ).

    DATA(lv_json_url) = c_base && '/swagger.json'.

    lv_path = mi_server->request->get_header_field( '~path' ).
    IF lv_path = c_base && '/swagger.html'.
      lo_swag->generate_ui(
        iv_json_url = lv_json_url
        iv_title    = 'abapGitServer - Swagger'(008) ).
    ELSEIF lv_path = lv_json_url.
      lo_swag->generate_spec(
        iv_title       = 'abapGitServer'(010)
        iv_description = 'abapGitServer REST functions'(009) ).
    ELSE.
      lo_swag->run( ).
    ENDIF.

  ENDMETHOD.


  METHOD zif_swag_handler~meta.

    FIELD-SYMBOLS: <ls_meta> LIKE LINE OF rt_meta.

    APPEND INITIAL LINE TO rt_meta ASSIGNING <ls_meta>.
    <ls_meta>-summary   = 'List Repositories'(001).
    <ls_meta>-url-regex = '/list$'.
    <ls_meta>-method    = zcl_swag=>c_method-get.
    <ls_meta>-handler   = 'LIST_REPOS'.

    APPEND INITIAL LINE TO rt_meta ASSIGNING <ls_meta>.
    <ls_meta>-summary   = 'List Branches'(002).
    <ls_meta>-url-regex = '/branches/(\w*)$'.
    APPEND 'IV_REPO' TO <ls_meta>-url-group_names.
    <ls_meta>-method    = zcl_swag=>c_method-get.
    <ls_meta>-handler   = 'LIST_BRANCHES'.

    APPEND INITIAL LINE TO rt_meta ASSIGNING <ls_meta>.
    <ls_meta>-summary   = 'Create repository'(003).
    <ls_meta>-url-regex = '/create$'.
    <ls_meta>-method    = zcl_swag=>c_method-post.
    <ls_meta>-handler   = 'CREATE_REPO'.

    APPEND INITIAL LINE TO rt_meta ASSIGNING <ls_meta>.
    <ls_meta>-summary   = 'List files'(004).
    <ls_meta>-url-regex = '/tree/(\w*)/(\w*)$'.
    APPEND 'IV_REPO' TO <ls_meta>-url-group_names.
    APPEND 'IV_BRANCH' TO <ls_meta>-url-group_names.
    <ls_meta>-method    = zcl_swag=>c_method-get.
    <ls_meta>-handler   = 'LIST_FILES'.

    APPEND INITIAL LINE TO rt_meta ASSIGNING <ls_meta>.
    <ls_meta>-summary   = 'Read blob'(005).
    <ls_meta>-url-regex = '/blob/(\w*)/(\w+)/(.*)$'.
    APPEND 'IV_REPO' TO <ls_meta>-url-group_names.
    APPEND 'IV_BRANCH' TO <ls_meta>-url-group_names.
    APPEND 'IV_FILENAME' TO <ls_meta>-url-group_names.
    <ls_meta>-method    = zcl_swag=>c_method-get.
    <ls_meta>-produce   = zcl_swag=>c_content_type-text_plain.
    <ls_meta>-handler   = 'READ_BLOB'.

    APPEND INITIAL LINE TO rt_meta ASSIGNING <ls_meta>.
    <ls_meta>-summary   = 'Read commit'(006).
    <ls_meta>-url-regex = '/commit/(\w+)$'.
    APPEND 'IV_COMMIT' TO <ls_meta>-url-group_names.
    <ls_meta>-method    = zcl_swag=>c_method-get.
    <ls_meta>-handler   = 'READ_COMMIT'.

    APPEND INITIAL LINE TO rt_meta ASSIGNING <ls_meta>.
    <ls_meta>-summary   = 'List commits'(007).
    <ls_meta>-url-regex = '/commits/(\w+)/(\w+)$'.
    APPEND 'IV_REPO' TO <ls_meta>-url-group_names.
    APPEND 'IV_BRANCH' TO <ls_meta>-url-group_names.
    <ls_meta>-method    = zcl_swag=>c_method-get.
    <ls_meta>-handler   = 'LIST_COMMITS'.

  ENDMETHOD.
ENDCLASS.