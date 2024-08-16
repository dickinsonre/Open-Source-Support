network = WSApplication.current_network()

network.transaction_begin()

network.row_objects_selection("_links").each do |link|
  link["bends"] = [link.us_node["X"], link.us_node["Y"], link.ds_node["X"], link.ds_node["Y"]]
  link.write
end

network.transaction_commit()