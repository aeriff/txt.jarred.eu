use_helper Nanoc::Helpers::Rendering

def title_for(item)
  if item[:title]
    "#{item[:title]} | txt.jarred.eu"
  else
    "txt.jarred.eu"
  end
end
