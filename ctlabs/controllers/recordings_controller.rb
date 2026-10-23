# -----------------------------------------------------------------------------
# File        : ctlabs/controllers/recordings_controller.rb
# Description : Serve and manage terminal walkthrough recordings (asciicast)
# License     : MIT License
# -----------------------------------------------------------------------------

class RecordingsController < BaseController
  # The Walkthrough page lives at /demo (MainController); these routes only
  # deal with the cast files themselves.

  get '/recordings' do
    redirect '/demo'
  end

  get '/recordings/:id' do
    path = RecordingService.path_for(params[:id])
    halt 404, 'Recording not found' unless path

    if params[:download]
      send_file path,
                filename:    File.basename(path),
                type:        'application/x-asciicast',
                disposition: 'attachment'
    else
      # Inline so the player can fetch() it; kept out of public/ so basic auth
      # applies and the id can never resolve outside the recordings directory.
      send_file path,
                type:        'application/x-asciicast; charset=utf-8',
                disposition: 'inline'
    end
  end

  post '/recordings/:id/delete' do
    halt 403, 'Invalid recording id' unless RecordingService.valid_id?(params[:id])

    deleted = RecordingService.delete(params[:id])
    halt 404, 'Recording not found' unless deleted

    redirect '/demo'
  end
end
