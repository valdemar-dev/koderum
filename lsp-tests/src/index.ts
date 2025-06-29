// 1. Directives and Pragmas
'use strict';
/// <reference path="types/global.d.ts" />
// @ts-nocheck

// 2. Imports and Exports
import fs, { readFileSync as readFile } from 'fs';
import type { PathLike } from 'fs';
import * as os from 'os';
export const PI = 3.14;
export default function main() {}
export { main as run };
export * from './utils';
export type { Utils } from './utils';
declare module 'custom-module' { interface Custom {} }
export = main;
export as namespace MyLib;
// 3. Ambient Declarations
declare function alert(message: string): void;
declare global { interface Window { custom: any; } }

window.p = () => "";

// 4. Variables & Literals
var v: number = 0;
let l = 123_456;
const c = 0b1010_1010n; // BigInt
const hex = 0xFF;
const oct = 0o744;
const str: string = `template ${v}`;
const tagged = tag`value`;
const regex = /ab+c/i;

// 5. Types & Interfaces
type Primitive = string | number | boolean;
interface Person { readonly id: unique symbol; name?: string; }
interface Employee extends Person { department: string; }
enum Color { Red, Green = 2, Blue }
const enum E { A, B }

// 6. Type Operators
type Keys = keyof Employee;
type PartialEmployee = Partial<Employee>;
type PickName = Pick<Employee, 'name'>;
type Conditional<T> = T extends string ? string : number;
type Inferred<T> = T extends Array<infer U> ? U : never;
type LiteralType = 'a' | 'b';
type TemplateLiteral = `pre${string}`;

type Mapped<T> = { [P in keyof T]-?: T[P] };

// 7. Functions
function fn(a: number = 0, ...rest: string[]): string { return `${a} ${rest.join(',')}`; }
function* gen(i = 0): Generator<number, void, unknown> { yield* [i, i+1]; }
async function asyncFn(): Promise<void> { await Promise.resolve(); }
const arrow = (x: number): number => x * 2;
const asyncGen = async function*(): AsyncGenerator<string> { yield 'a'; };

// Overloads
function overload(x: string): string;
function overload(x: number): number;
function overload(x: any) { return x; }

// 8. Classes & Decorators
function deco(target: any, key: string) {}
@deco
abstract class Base<T> {
  static count = 0;
  #privateField: T;
  constructor(public value: T) { Base.count++; }
  get val(): T { return this.value; }
  set val(v: T) { this.value = v; }
  abstract method(): void;
}
class Derived extends Base<number> implements Person {
  readonly id = Symbol();
  department = 'dev';
  static {
    // static initialization block
    console.log('init');
  }
  method() {}
}

// Mixins
type Constructor<T = {}> = new (...args: any[]) => T;
function Mixin<TBase extends Constructor>(Base: TBase) {
  return class extends Base { mixed = true; };
}
class Mixed extends Mixin(Derived) {}

// 9. Control Flow
labelled: for (const key in {a:1}) {
  if (key === 'a') break labelled;
}
for (const val of [1,2,3]) {}
for await (const p of Promise.all([Promise.resolve(1)])) {}
while (false) {}
do {} while (false);
switch (v) { case 0: default: break; }
try { throw new Error(); } catch { } finally { console.log('done'); }

// 10. Operators & Expressions
const opt = obj?.prop?.[0] ?? 'default';
const coerced = <string>str;
const asserted = str!;
const assign = { ...obj, new: true };
const restObj = ({a, ...rest} = obj, rest);

const meta = import.meta;
(async () => { const dyn = await import('./dynamic'); })();

// 11. Proxy & Reflect
const proxy = new Proxy(obj, { get(t, k) { return Reflect.get(t, k); } });

// 12. Other Constructs
debugger;
with (({a:1} as any)) { console.log(a); }
throw 'error';
return; // top-level return invalid but present in snippet

// JSDoc
/** @deprecated */ function old() {}

// assert
function assertIsString(x: any): asserts x is string { if (typeof x !== 'string') throw new Error(); }

// End of syntactical showcase
