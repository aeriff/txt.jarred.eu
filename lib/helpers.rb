use_helper Nanoc::Helpers::Rendering
use_helper Nanoc::Helpers::LinkTo

def title_for(item)
  if item[:title]
    "#{item[:title]} | txt.jarred.eu"
  else
    "txt.jarred.eu"
  end
end
