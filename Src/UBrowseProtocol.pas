{
 * UBrowseProtocol.pas
 *
 * Implements a abstract base class for protocol handlers that access a URL
 * using a TBrowseURL action.
 *
 * $Rev$
 * $Date$
 *
 * ***** BEGIN LICENSE BLOCK *****
 *
 * Version: MPL 1.1
 *
 * The contents of this file are subject to the Mozilla Public License Version
 * 1.1 (the "License"); you may not use this file except in compliance with the
 * License. You may obtain a copy of the License at http://www.mozilla.org/MPL/
 *
 * Software distributed under the License is distributed on an "AS IS" basis,
 * WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License for
 * the specific language governing rights and limitations under the License.
 *
 * The Original Code is UBrowseProtocol.pas
 *
 * The Initial Developer of the Original Code is Peter Johnson
 * (http://www.delphidabbler.com/).
 *
 * Portions created by the Initial Developer are Copyright (C) 2009 Peter
 * Johnson. All Rights Reserved.
 *
 * Contributors:
 *   NONE
 *
 * ***** END LICENSE BLOCK *****
}


unit UBrowseProtocol;


interface


uses
  // Project
  UProtocols;


type

  {
  TBrowseProtocol:
    Abstract base class for protocol handlers that access a URL using a
    TBrowseURL action.
  }
  TBrowseProtocol = class abstract(TProtocol)
  strict protected
    class function NormaliseURL(const URL: string): string; virtual;
      {Converts URL into its normal form. Does nothing by default. Descendants
      may override.
        @param URL [in] URL to be normalised.
        @return URL unchanged.
      }
  public
    class function SupportsProtocol(const URL: string): Boolean;
      override; abstract;
      {Checks if this protocol handler handles a URL's protocol.
        @param URL [in] URL whose protocol is to be checked.
        @return True if URL's protocol is supported, False if not.
      }
    function Execute: Boolean; override;
      {Executes resource using a TBrowseAction to display URL in default
      application for file type.
        @return True.
      }
  end;


implementation


uses
  // Delphi
  SysUtils, ExtActns;


{ TBrowseProtocol }

function TBrowseProtocol.Execute: Boolean;
  {Executes resource using shell to display URL in default application for file
  type.
    @return True.
    @except EProtocol raised if an exception occurs in browse action.
  }
begin
  // We execute the resource using an action
  try
    with TBrowseURL.Create(nil) do
      try
        URL := NormaliseURL(Self.URL);
        Execute;
        Result := True;
      finally
        Free;
      end;
  except
    // any exceptions converted to EProtocol
    on E: Exception do
      raise EProtocol.Create(E);
  end;
end;

class function TBrowseProtocol.NormaliseURL(const URL: string): string;
  {Converts URL into its normal form. Does nothing by default. Descendants may
  override.
    @param URL [in] URL to be normalised.
    @return URL unchanged.
  }
begin
  Result := URL;
end;

end.

