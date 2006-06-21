module WWW
# Class Form does not work in the case there is some invalid (unbalanced) html
# involved, such as: 
#
#   <td>
#     <form>
#   </td>
#   <td>
#     <input .../>
#     </form>
#   </td>
# 
# GlobalForm takes two nodes, the node where the form tag is located
# (form_node), and another node, from which to start looking for form elements
# (elements_node) like buttons and the like. For class Form both fall together
# into one and the same node.
  class GlobalForm
    attr_reader :form_node, :elements_node
    attr_accessor :method, :action, :name
  
    attr_finder :fields, :buttons, :file_uploads, :radiobuttons, :checkboxes
    attr_reader :enctype
  
    def initialize(form_node, elements_node)
      @form_node, @elements_node = form_node, elements_node
  
      @method = (@form_node.attributes['method'] || 'GET').upcase
      @action = @form_node.attributes['action'] 
      @name = @form_node.attributes['name']
      @enctype = @form_node.attributes['enctype'] || 'application/x-www-form-urlencoded'
      @clicked_buttons = []
  
      parse
    end
  
    # In the case of malformed HTML, fields of multiple forms might occure in this forms'
    # field array. If the fields have the same name, posterior fields overwrite former fields.
    # To avoid this, this method rejects all posterior duplicate fields.
  
    def uniq_fields!
      names_in = {}
      fields.reject! {|f|
        if names_in.include?(f.name)
          true
        else
          names_in[f.name] = true
          false
        end
      }
    end
  
    def build_query(buttons = [])
      query = []
  
      fields().each do |f|
        next unless f.value
        query << [f.name, f.value]
      end
  
      checkboxes().each do |f|
        query << [f.name, f.value || "on"] if f.checked
      end
  
      radio_groups = {}
      radiobuttons().each do |f|
        radio_groups[f.name] ||= []
        radio_groups[f.name] << f 
      end
  
      # take one radio button from each group
      radio_groups.each_value do |g|
        checked = g.select {|f| f.checked}
  
        if checked.size == 1
          f = checked.first
          query << [f.name, f.value || ""]
        elsif checked.size > 1 
          raise "multiple radiobuttons are checked in the same group!" 
        end
      end

      @clicked_buttons.each { |b|
        b.add_to_query(query)
      }
  
      query
    end

    def add_button_to_query(button)
      @clicked_buttons << button
    end
  
    def request_data
      query_params = build_query()
      query = nil
      case @enctype.downcase
      when 'multipart/form-data'
        boundary = rand_string(20)
        @enctype << ", boundary=#{boundary}"
        params = []
        query_params.each { |k,v| params << param_to_multipart(k, v) }
        @file_uploads.each { |f| params << file_to_multipart(f) }
        query = params.collect { |p| "--#{boundary}\r\n#{p}" }.join('') +
          "--#{boundary}--\r\n"
      else
        query = WWW::Mechanize.build_query_string(query_params)
      end
  
      query
    end
  
    def parse
      @fields       = WWW::Mechanize::List.new
      @buttons      = WWW::Mechanize::List.new
      @file_uploads = WWW::Mechanize::List.new
      @radiobuttons = WWW::Mechanize::List.new
      @checkboxes   = WWW::Mechanize::List.new
  
      @elements_node.each_recursive {|node|
        case node.name.downcase
        when 'input'
          case (node.attributes['type'] || 'text').downcase
          when 'text', 'password', 'hidden', 'int'
            @fields << Field.new(node.attributes['name'], node.attributes['value'] || '') 
          when 'radio'
            @radiobuttons << RadioButton.new(node.attributes['name'], node.attributes['value'], node.attributes.has_key?('checked'))
          when 'checkbox'
            @checkboxes << CheckBox.new(node.attributes['name'], node.attributes['value'], node.attributes.has_key?('checked'))
          when 'file'
            @file_uploads << FileUpload.new(node.attributes['name'], node.attributes['value']) 
          when 'submit'
            @buttons << Button.new(node.attributes['name'], node.attributes['value'])
          when 'image'
            @buttons << ImageButton.new(node.attributes['name'], node.attributes['value'])
          end
        when 'textarea'
          @fields << Field.new(node.attributes['name'], node.all_text)
        when 'select'
          @fields << SelectList.new(node.attributes['name'], node)
        end
      }
    end

    def inspect
      string = "Form: ['#{@name}' -> #{@action}]\n"
      string << "[radiobuttons]\n"
      @radiobuttons.each { |f| string << f.inspect }
      string << "[checkboxes]\n"
      @checkboxes.each { |f| string << f.inspect }
      string << "[fields]\n"
      @fields.each { |f| string << f.inspect }
      string << "[buttons]\n"
      @buttons.each { |f| string << f.inspect }
      string
    end
  
    private
    def rand_string(len = 10)
      chars = ("a".."z").to_a + ("A".."Z").to_a
      string = ""
      1.upto(len) { |i| string << chars[rand(chars.size-1)] }
      string
    end
  
    def mime_value_quote(str)
      str.gsub(/(["\r\\])/){|s| '\\' + s}
    end

    def param_to_multipart(name, value)
      return "Content-Disposition: form-data; name=\"" +
              "#{mime_value_quote(name)}\"\r\n" +
              "\r\n#{value}\r\n"
    end
  
    def file_to_multipart(file)
      body =  "Content-Disposition: form-data; name=\"" +
              "#{mime_value_quote(file.name)}\"; " +
              "filename=\"#{mime_value_quote(file.file_name)}\"\r\n" +
              "Content-Transfer-Encoding: binary\r\n"
      if file.mime_type != nil
        body << "Content-Type: #{file.mime_type}\r\n"
      end
  
      body << "\r\n#{file.file_data}\r\n"
  
      body
    end
  end
  
  class Form < GlobalForm
    attr_reader :node
  
    def initialize(node)
      @node = node
      super(@node, @node)
    end

    # Fetch the first field whose name is equal to field_name
    def field(field_name)
      fields.find { |f| f.name.eql? field_name }
    end
  end
end