shared_context "an endpoint definition", :uses_request_params_parser_definition do
  let_without_indentation(:endpoint_definition_yml) do <<-EOF
    ---
    name: project_list
    route: /users/:user_id/projects/:project_language
    method: GET
    definitions:
      - versions: ["1.0"]
        message_type: request
        path_params:
          type: object
          properties:
            user_id:
              type: string
              pattern: '^\\d+\\.\\d+$'
            project_language:
              type: string
              enum: [ruby, python, perl]
        query_params:
          type: object
          properties:
            integer:
              type: integer
              optional: true
            number:
              type: number
              optional: true
            boolean:
              type: boolean
              optional: true
            null_param:
              type: "null"
              optional: true
            date:
              type: string
              format: date
              optional: true
            date_time:
              type: string
              format: date-time
              optional: true
            uri:
              type: string
              format: uri
              optional: true
            union:
              optional: true
              type:
                - boolean
                - integer
                - number
                - "null"
                - type: string
                  format: date
                - type: string
                  format: date-time
                - type: string
                  format: uri
            uri_or_date:
              optional: true
              type:
                - type: string
                  format: uri
                - type: string
                  format: date
        schema: {}
        examples: {}
    EOF
  end
end
