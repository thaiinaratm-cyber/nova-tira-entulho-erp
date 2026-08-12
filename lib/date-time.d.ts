export const APP_TIME_ZONE:string;
export function formatDateTime(value:string|Date|null|undefined,fallback?:string):string;
export function formatDateOnly(value:string|Date|null|undefined,fallback?:string):string;
export function toLocalInputValue(value?:string|Date):string;
export function saoPauloInputToIso(value:string):string;
