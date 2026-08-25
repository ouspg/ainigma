export const MOBILE_NAV_REQUEST_EVENT = "ainigma:mobile-navigation-request";
export const MOBILE_NAV_STATE_EVENT = "ainigma:mobile-navigation-state";

export interface MobileNavRequestDetail {
  isOpen: boolean;
}

export interface MobileNavStateDetail {
  isOpen: boolean;
}
