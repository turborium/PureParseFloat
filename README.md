# PureParseFloat [en]

**PureParseFloat - This is a simple and clear, "clean" algorithm and implementation of a function for converting a string to a double number, with OK accuracy.**
**The main feature of the algorithm that underlies this implementation is the trade-off between simplicity, accuracy, and speed.**

**PureParseFloat** provides accurate conversion of numbers with a mantissa up to 31 bits, in the exponent range from -291 to +308, otherwise the conversion can have a maximum error of 1 ULP, which means that for most numbers encountered in practice the conversion will be absolutely accurate.
In general, this implementation adheres to the idea of "a fairly good and at the same time simple floating point parser."

There are two "reference" implementations available in this repository, for Pascal and C. Both implementations are covered with tests on millions of values, however the "main" implementation is the Pascal version.  

Pascal version tested on Delphi and FreePascal, C version tested on TDM-GCC.  

Warning: the algorithm needs double aritmetic exactly matching the ieee standard, so before using the ParseFloat function, you must set the FPU precision to Double/64bit and rounding to Nearest. In ObjectPascal there are standard function for this, which are used by the Pascal reference implementation, but for C you need to do this yourself.  

# PureParseFloat [ru]

**PureParseFloat - Это простая и понятная, "чистая", реализация функции для преобразования строки в число формата double, с достаточно хорошей точностью.**  
**Главная особенность алгоритма, который лежит в основе этой реализации, это компромисс между простотой, точносью, и скоростью.**  

**PureParseFloat** обеспечивает точное преобразование чисел с мантиссой до 31 разряда, в диапазоне экспоненты от -291 до +308, в противном случае преобразование может иметь максимальную ошибку в 1 ULP, это означает, что для большинства встречающихся на практике чисел перобразование будет абсолютно точным.    
В целом эта реализация придерживается идеи "достаточно хороший и при этом простой парсер чисел с плавающей запятой".  

В этом репозитории доступны две "референсные" реализации, для Pascal и C. Обе реализации покрыты тестами на миллионы значений, однако "главной" реализацией являеться Pascal версия.  

Pascal версия протестирована в Delphi и FreePascal, С версия протистирована в TDM-GCC.  

Внимание: алгоритм полагается на точное соответсвие double стандарту ieee, поэтому перед использованием функции ParseFloat необходимо установить точность математического сопроцессора в Double/64bit, а округление в "ближайшее"/Nearest. В ObjectPascal для этого есть стандартные средства, котрые использует референсная Pascal реализация, для C же необходимо это сделать самостоятельно.  

## Проблематика
Преобразование строки в число формата double, на удивление, является довольно [сложной](https://www.exploringbinary.com/topics/#correctly-rounded-decimal-to-floating-point) и комплексной задачей.  
Из-за ограниченой точности чисел формата Double, простые алгоритмы преобразования, часто, дают ошибку в несколько ULP (+/- несколько единиц двоичной мантиссы). Описание простого алгорита преобразования есть ниже, а также в [статье](https://www.exploringbinary.com/quick-and-dirty-decimal-to-floating-point-conversion/).  

В стандартной библиотеке многих компиляторов и интерпритаторов есть функции преобразования строки в число подверженные некоторой неточности, а стандарты языков программирования как правило не уточняют ничего о точности преобразования.  

**Примеры проблем:**  
- **Visual Studio C++** более 20 лет [включала неточную версию функции **strtod**](https://www.exploringbinary.com/incorrectly-rounded-conversions-in-visual-c-plus-plus/), а исправление потребовало [множество итераций](https://www.exploringbinary.com/visual-c-plus-plus-strtod-still-broken/). Классический **С RTL** - **'MSVCRT.DLL'**, включенный в **Windows**, все еще имеет "неточную" версию **strtod**.
- Исправление ошибок округления в **GNU GCC** [потребовало множество лет и итераций](https://www.exploringbinary.com/incorrectly-rounded-conversions-in-gcc-and-glibc/), и в конце концов [увенчалось успехом](https://www.exploringbinary.com/real-c-rounding-is-perfect-gcc-now-converts-correctly/), благодаря переходу на использование сторонней, "тяжелой", библиотеки [**MPFR**](https://www.mpfr.org/), которая использует "тяжелую" библиотеку [**GMPLIB**](https://gmplib.org/) для длинных вычислений. Однако в **GCC**, все еще, есть [некоторые проблемы](https://lemire.me/blog/2020/06/26/gcc-not-nearest/) с точностью.
- В **Delphi**, все еще, используется простой алгоритм подверженный ошибкам, особенно в **x64**, т.к. в **x64** используется **double**, а не более точный **extended** для преобразования.
  
Несмотря на то, что для большинства приложений, ошибка в несколько **ULP** не являеться реальной проблемой, в определеных задачах хотелось бы иметь достаточно точное и стабильное преобразование, не зависящее от разрядности, компилятора, языка программирования и т.д..  

Одно из решений для преобразования строки в double это алгоритм авторства **David M. Gay** описанный в [**"Correctly Rounded Binary-Decimal
and Decimal-Binary Conversions"**](https://www.ampl.com/archive/first-website/REFS/rounding.pdf), реализованный автором алгоритма в виде библиотеки [**netlib dtoa.c**](https://portal.ampl.com/~dmg/netlib/fp/dtoa.c).  
Стоит отметить, что именно **David M. Gay** один из первых поднял "проблематику" неточных преобразований строки в число, и предложил свое решение.  
Однако, несмотря на то, что даная реализация часто используется как "референсная", они имеет некотрые проблемы, такие как сложность и подверженность фатальным ошибкам. Файл **dtoa.c** имеет более **6000** строк кода, имеет очень большую цикломатическую сложность, большую вложенность, множество магических чисел, операторов goto.  

**Некоторые примеры проблем которые вызвало использование netlib dtoa.c:**  
- [Переполнение буффера](https://bugzilla.mozilla.org/show_bug.cgi?id=516396) при специально подготовленном длином числе в строке (уязвимость была в **FireFox**, **Safari**, **Chrome**, **Ruby**)
- [Фатальное зацикливание](https://news.ycombinator.com/item?id=2164863) при преобразовании строки **"2.2250738585072011e-308"**, которое приводило к зависанию [**PHP**](https://www.exploringbinary.com/php-hangs-on-numeric-value-2-2250738585072011e-308/) и [**Java**](https://www.exploringbinary.com/java-hangs-when-converting-2-2250738585072012e-308/)
- [Фатальная неточность](https://patrakov.blogspot.com/2009/03/dont-use-old-dtoac.html) в преобразовании: "1.1" -> 11.0 (получение полностью неверного числа для корректной строки)
- [Неточное преобразование](https://www.exploringbinary.com/incorrect-directed-conversions-in-david-gays-strtod/)
- [Ошибка на 1 ULP](https://www.exploringbinary.com/a-bug-in-the-bigcomp-function-of-david-gays-strtod/)
  
Несмотря на то, что на данный момент, все перечисленные баги были [исправлены](https://portal.ampl.com/~dmg/netlib/fp/changes), нельзя быть на 100% увереным в отсутствии других "фатальных" багов. Кроме того, реализция [**netlib dtoa.c**](https://portal.ampl.com/~dmg/netlib/fp/dtoa.c) настолько сложна, что переписать ее на другой язык является крайне сложной задачей, с очень большой вероятностью внести, при переписывании, дополнительные ошибки.  
А если учитывать, что переписаная на [**Java версия имела баг, с зависанием,**](https://www.exploringbinary.com/java-hangs-when-converting-2-2250738585072012e-308/), от референсной **C** реализации, можно сделать вывод, что понимание того как в действительности работает [**netlib dtoa.c**](https://portal.ampl.com/~dmg/netlib/fp/dtoa.c) имеет только один человек - автор данного алгоритма и реализации, что, на взгляд автора данной статьи, являеться просто "безумным", учитывя "базовость", концепции преобразования строчки в число.  

В 2020 году появился новый алгоритм преобразования [**Daniel Lemire fast_double_parser**](https://github.com/lemire/fast_double_parser), а также его улучшенная реализация [**fast_float**](https://github.com/fastfloat/fast_float).  
Главным плюсом данного алгоритма являеться наличие понятного, хотябы в общих чертах, описания, а также наличие [нескольких реализаций](https://github.com/lemire/fast_double_parser#ports-and-users) на [нескольких языках](https://github.com/fastfloat/fast_float#other-programming-languages). Существует также ["вводное" описание алгоритма](https://nigeltao.github.io/blog/2020/eisel-lemire.html). Главным же плюсаом, на взгляд автора статьи, является намного меньшая сложность в сравнении с **netlib dtoa.c**.

**Некоторые минусы алгоритма Daniel Lemire:**
- Местами меньшая скорость чем у **netlib dtoa.c**
- Все еще высокая сложность, что делает его понимание практически невозможным для большинства программистов (несколько тысяч строк при полной реализации на **С++**)
- Наличие "тяжелых" таблиц (не подходит для слабых микроконтроллеров с малым количеством памяти)
- Использование "дорогой" длиной арифметики для некоторых "сложных" чисел, что делает время преобразования сильно недетерминированным (время преобразования моежт возрастать на порядок из-за небольшого изменения входных данных)

Исходя из выше описанных плюсов и минусов, можно сделать вывод, что относительно новый алгоритм **Daniel Lemire** может быть хорошим выбором во многих случаях. Однако и он сликом сложен для понимания большинства программистов. Кроме того, несмотря на наличие нескольких описаний, конкретные реализации имеют некоторые "магические" числа, кочующиее из одной реализации в другую, предположительно методом "копипаста". В текущих реализациях "резервного алгоритма"(с использованием длинной арифметики) используется буффер цифр фиксированного размера, с коменариями ["должно быть достаточно"](https://github.com/google/wuffs/blob/ba3818cb6b473a2ed0b38ecfc07dbbd3a97e8ae7/internal/cgen/base/floatconv-submodule-code.c#L160C77-L160C77), что не дает быть уверенным, что мы всегда получим "безупречную" точность.  

Изучив плюсы и минусы выше пречисленных алгоритмов был разработан новый "достаточно хороший" алгоритм **Pure Parse Float** для преобразования строчки в число **double**.   
Новый алгоритм имеет среднюю скорость, достаточную точность, стабильность, и максимальную простоту.   
Таким образом, если вам важна понятность, небольшой размер (в том числе в бинарном виде), отсутствие "скрытых" критических багов, которые могут привести к зависанию, переполнению буффера, или фатальной неточности, из-за слишком большой сложности, но при этом вы готовы к небольшому количеству отклонений в **1 ULP** на граничных случаях, то алгоритм **Pure Parse Float** является оптимальным выбором. (В самом худшем случае, если в алгоритме есть ошибки - при преобразовании выйдет ошибка в небольшом количестве **ULP**)

## Алгоритм

Так как алгоритм **Pure Parse Float** основан на простом алгоритме преобразования, то сначала рассмотрим простой алгоритм преобразования строчки в double.

### Простой алгоритм преобразования строки в double
1) Необходимо сконвертировать строчку в структуру FixedDecimal следующего вида:
```
TDigitsArray = array [0 .. 16] of Byte;// Массив цифр, размер массива равен максимальному количеству десятичных цифр в Double (17 цифр)
TFixedDecimal = record
  Count: Integer;// Количество цифр
  Exponent: Integer;// Экспонента числа
  IsNegative: Boolean;// Негативное число
  Digits: TDigitsArray;// Цифры (мантисса)
end;
```
*Пример для строчки "123.45":*
```
Count = 5;
Exponent = 2;
IsNegative = False;
Digits = [1, 2, 3, 4, 5];
```
2) Зануляем результат:
```
Result := 0.0;
```
3) Записываем цифры числа(мантиссу) в Result, умножая Result на 10 и добавляя очередную цифру, пока не запишем все цифры:
```
for I := 0 to Decimal.Count - 1 do
begin
  Result := Result * 10;// * 10
  Result := Result + Decimal.Digits[I];// + Digit
end;
```
4) Корректируем экспоненту числа:
```
Exponent := Decimal.Exponent - Decimal.Count + 1; // Разница между необходимой и текущей экспонентой 
Result := Result * Power(10.0, Exponent); // фиксим степень
```
5) Корректируем знак числа:
```
if Decimal.IsNegative then
begin
  Result := -Result;
end;
```

Этот алгоритм для входных строк в диапазоне **double** в ~60% будет выдавать правильно округленный результат, в ~30% отклонение будет в **1 ULP**, и в ~10% отклонение будет больше чем **1 ULP**.  
Стоит отметить, что "неточности" складываються. Например, если некоторое число было неверно округлено при формировании мантиссы, например, из-за того что в нем было больше 15 цифр, то это даст ошибку в **1 ULP**, а если при установке порядка произошло еще одно неверное округление, то выйдет ошибка в еще несколько **ULP**, таким образом общая ошибка может быть больше **1 ULP**.  
В целом, совсем "фатально" неверных результатов преобразования получить нельзя, однако "чучуть" неточных результатов слишком много. В худшем случае до +/-20 ULP.  

Основной причиной неточности "простого" алгоритма является преждевременное округление результата, из-за физического ограничения количества битов хранящих число формата double. В double может поместиться 15-18 десятичных цифр, реально же гарантируется 15.  
Например, для вполне валидной(для double) строки "18014398509481993" с 17 цифрами простой алгоритм выдаст результат с ошбикой в **1 ULP**, из-за того, что double гарантировано хранит лишь 15-17 десятичных цифр, и при попытке "внести" вполне корректное число с 17 цифрами, мы превышаем всегда гарантированые 15 цифр, что, на конкретно этом числе, приводит к неверному округлению. Для строки же "18014398509481993e71" уже неверно внесенные 17 цифр еще и умножаются на степень 10, что еще дополнительно увеличивает ошибку. Кроме того функция возведения числа в степень сама может иметь некоторую неточность(в большинстве реализаций), что может еще сильнее увеличить ошибку.  
Интересно здесь то, что буквально 1 бита мантиссы хватило бы для верного округления.  

Теперь рассмотрим алгоритм Pure Parse Float.

### Алгоритм Pure Parse Float

Алгоритм Pure Parse Float в общих чертах аналогичен простому алгоритму, но для промежуточных вычислений использует числа формата double-double.  

Арифметика double-double - это описанный в статье T. J. Dekker ["A Floating-Point Technique for Extending the Available Precision"](https://csclub.uwaterloo.ca/~pbarfuss/dekker1971.pdf) метод реализации float-point, почти четырехкратной точности, с использованием пары значений double. Используя два значения IEEE double с 53-битной мантиссой, арифметика double-double обеспечивает операции с числами, мантисса которых не меньше 2 * 53 = 106 бит.  
Однако диапазон(экспонента) double-double остается таким же, как и у формата double.  
Числа double-double имеют гарантированную точность в 31 десятичную цифру, за исключением показателей степени меньше -291 (exp^2 >= -968), из-за денормализованных чисел, где точность double-double постепенно уменьшается до обычного double.  
Небольшой обзор дабл-дабла доступен здесь в этой [статье](https://en.wikipedia.org/wiki/Quadruple-precision_floating-point_format#Double-double_arithmetic).  
Дополнительная информация о double-double представлена в референсной Pascal реализации.  
Ключевой особенностью double-double является то, что число double-double представлено в виде Hi + Lo, где Hi - это правильно округленное значение «главного» числа, а Lo — это некий «Остаток».  
Например: '123456789123456789123456789' представлено в виде '1.2345678912345679e+26' + '-2.214306027e+9'.  
Существует простое объяснение double-double в виде [статьи](https://habr.com/ru/articles/423469/) и в виде [ролика](https://www.youtube.com/watch?v=6OuqnaHHUG8).  

Итак, ключевой идеей Pure Parse Float является то, что double-double арифметика позволяет проводить вычисления с большей точностью, получая, в Hi части double-double числа, правильно округленное значение результата преобразования строчки в число.  

Таким образом, для чисел длиной до 31 цифры, и с экспонентой от -291 до +308, ошибка будет в **0 ULP**.  
Для денормализованных чисел в диапазоне экспоненты меньше -291 ошибка будет всего в 1 ULP, т.к. ошибка происходит единожды, при установке степени.  

Референсная Pascal реализация имеет доработанные методы работы с double-double арифметикой, с дополнениями позволяющими правильно обрабатывать такие числа как NaN/Infinity.  
Все методы работы с double-double имеют необходимые ссылки на их математическое доказательство, а все константы подробно объяснены.  
Также, для упрощения, функция возведения в степень не реализована, используется простой табличный метод и цикл. (Имеет смысл провести исследование на тему возведения в степень чисел формата double-double, возможно можно избавиться и от ошибки в 1 ULP, в области денормализованных чисел)    

Внимание: алгоритм полагается на точное соответсвие double стандарту ieee, поэтому перед использованием функции ParseFloat необходимо установить точность сопроцессора в Double/64bit, а округление в "ближайшее"/Nearest. В ObjectPascal для этого есть стандартные средства, котрые использует референсная Pascal реализация, для C же необходимо это сделать самостоятельно.  

Референсная реализация имеет минимальную "ручную" оптимизацию исходного текста для максимальной читабельности.  

## Тесты

Корректность работы Pure Parse Float была проверена на нескольких десятках миллионах входных строк, для чего была написана специальная тестовая программа.  
Тестовая программа также вклчает в себя бенчмарк, позволяющий сравнить производительность Pure Parse Float в сравнении с другими алгоритмами.  

Результат сравнения точности на всем диапазоне чисел:
| Parser                              | Regular Numbers Fails    | Long Numbers Fails        | Read/Write Double Fails  | Result |
|-------------------------------------|--------------------------|---------------------------|--------------------------|--------|
| PureParseFloat (x86/x64)            | 0.033%                   | 0.013%                    | 0.016%                   | OK     |
| Delphi StrToFloat (x86)             | 0.033%                   | 0.102%                    | 0.010%                   | OK     | 
| Delphi StrToFloat (x64)             | 39.106% / (7.872% >1ULP) | 71.897% / (47.451% >1ULP) | 31.434% / (0.934% >1ULP) | FAIL   |
| FreePascal StrToFloat (x64)         | 0.067%                   | 0.062%                    | 0.021%                   | OK     |
| Microsoft strtod (MSVCRT.DLL) (x86) | 0.987% / (0.407% >1ULP)  | 0.326% / (0.111% >1ULP)   | 0.018%                   | FAIL   |
| Microsoft strtod (MSVCRT.DLL) (x64) | 0.987% / (0.407% >1ULP)  | 0.326% / (0.111% >1ULP)   | 0.018%                   | FAIL   |

В качестве референса взяты результаты преобразования **netlib dtoa.c**, в которой, предположительно, уже "отловлены" большинство ошибок.  
Как видно из таблицы - x64 Delphi StrToFloat работает намного хуже, чем x86 версия, из-за упомянутого выше "округления" double, в x86 же вычисления присходят в более точном extended.  
Реализация от Microsoft имеет множество ошибок больших чем 1ULP.  
Реализация в FreePascal довольно хороша в точности.  
Однако, как видно из таблицы, Pure Parse Float обеспечивает самую лучшую точность, при всей своей простоте.  

Резуьтат сравнения скорости (меньше - лучше):

| Parser                        | Time (x86) | Time (x64) | 
|-------------------------------|------------|------------| 
| PureParseFloat (Delphi)       | 7058ms     | 2929ms     |  
| PureParseFloat (FreePascal)   |            | 2996ms     | 
| PureParseFloat (C, TDM-GCC)   | 15866ms(!) | 1992ms     | 
| Netlib strtod                 | 1656ms     | 1226ms     | 
| Delphi TextToFloat            | 692ms      | 1842ms     | 
| FreePascal TextToFloat        |            | 1685ms     | 
| Microsoft strtod              | 5488ms     | 3808ms     | 

Как можно видеть из таблицы - лидера по скорости нет, в зависимости от компилятора и разрядности получаются разные результаты.  
В целом ParseFloat имеет среднюю скорость, кроме аномально низкой скорости C версии, на x86, с компилятором GCC, вероятно причиной этому является активированая опция ```-ffloat-store```, без которй GCC [порождает неверный код](https://lemire.me/blog/2020/06/26/gcc-not-nearest/).  
В x64 версии - видны, те самые, ~20% разницы производительности между C и Pascal.  
Что интересно - скорость функции ParseFloat скомпилированной FreePascal и Delphi - примерно одинаковая, хотя известно что в FPC намного более "слабый" оптимизатор.  

Если вам интересно увидеть свою реализацию, для языка отсутсвующего в этой таблице, то создайте ее в соответсвующей директории, и приложите проект, создающий DLL для тестирования, аналогичный тому, что создан для C версии.  
